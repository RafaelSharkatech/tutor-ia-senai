import 'dotenv/config';
import { randomUUID } from 'node:crypto';
import { existsSync } from 'node:fs';
import pino from 'pino';
import {
  Room,
  RoomEvent,
  TrackKind,
  TrackSource,
  AudioSource,
  LocalAudioTrack,
  type RemoteAudioTrack,
  type RemoteTrack,
  type RemoteTrackPublication,
  TrackPublishOptions,
} from '@livekit/rtc-node';
import type { RoomOptions } from '@livekit/rtc-node';
import { AccessToken } from 'livekit-server-sdk';
import projectConfig from './shared/project_config.js';
import { createAudioSink } from './livekit/audioSink.js';
import type {
  AudioSink,
  AudioCaptureResult,
  SpeechSegmentInfo,
} from './livekit/audioSink.js';
import { ConversationPipeline } from './pipeline/conversation.js';
import type { ConversationPipelineOptions, ChatContextPayload } from './pipeline/conversation.js';

process.on('uncaughtException', (err) => {
  console.error('Uncaught exception:', err);
  process.exit(1);
});

process.on('unhandledRejection', (reason) => {
  console.error('Unhandled rejection:', reason);
  process.exit(1);
});

const workerDefaults = projectConfig.worker;
const defaultLivekitRoom = projectConfig.livekit.defaultRoom;
const workerIdentity = workerDefaults.defaultIdentity;
const idleTimeoutMs = Number.parseInt(
  process.env.WORKER_IDLE_TIMEOUT_MS ?? '90000',
  10,
);

if (
  !process.env.GOOGLE_APPLICATION_CREDENTIALS &&
  workerDefaults.googleApplicationCredentials &&
  existsSync(workerDefaults.googleApplicationCredentials)
) {
  process.env.GOOGLE_APPLICATION_CREDENTIALS =
    workerDefaults.googleApplicationCredentials;
}

if (!process.env.GOOGLE_CLOUD_PROJECT) {
  process.env.GOOGLE_CLOUD_PROJECT = projectConfig.firebase.projectId;
}

const logger = pino({
  transport: { target: 'pino-pretty', options: { colorize: true } },
});
const participantContexts = new Map<string, ChatContextPayload>();
interface SinkEntry {
  sink: AudioSink;
  participantIdentity?: string;
}

const audioSinks = new Map<string, SinkEntry>();

interface EnvConfig {
  host: string;
  apiKey: string;
  apiSecret: string;
  roomName: string;
  participantIdentity: string;
}

function loadEnv(): EnvConfig {
  const {
    LIVEKIT_HOST = projectConfig.livekit.host,
    LIVEKIT_API_KEY = projectConfig.livekit.apiKey,
    LIVEKIT_API_SECRET = projectConfig.livekit.apiSecret,
    LIVEKIT_ROOM = defaultLivekitRoom,
    WORKER_IDENTITY = workerIdentity,
  } = process.env;

  if (!LIVEKIT_HOST || !LIVEKIT_API_KEY || !LIVEKIT_API_SECRET) {
    throw new Error('Missing LiveKit environment variables.');
  }

  return {
    host: LIVEKIT_HOST,
    apiKey: LIVEKIT_API_KEY,
    apiSecret: LIVEKIT_API_SECRET,
    roomName: LIVEKIT_ROOM,
    participantIdentity: WORKER_IDENTITY,
  };
}

async function createToken(env: EnvConfig): Promise<{ url: string; token: string }> {
  const normalizedHost = env.host.startsWith('ws')
    ? env.host
    : env.host.replace(/^http/, 'ws');

  const accessToken = new AccessToken(env.apiKey, env.apiSecret, {
    identity: env.participantIdentity,
    ttl: 60 * 60,
    metadata: JSON.stringify({
      role: 'assistant',
      source: 'worker',
    }),
  });

  accessToken.addGrant({
    roomJoin: true,
    room: env.roomName,
    canPublish: true,
    canSubscribe: true,
    canPublishData: true,
  });

  const token = await accessToken.toJwt();
  return { url: normalizedHost, token };
}

async function publishPacket(
  room: Room,
  type: string,
  payload: Record<string, unknown> = {},
  reliable = true,
): Promise<void> {
  const participant = room.localParticipant;
  if (!participant) {
    logger.warn({ type }, 'Local participant unavailable; cannot publish data packet');
    return;
  }
  const envelope = {
    type,
    payload,
    sentAt: new Date().toISOString(),
  };
  try {
    const data = Buffer.from(JSON.stringify(envelope), 'utf8');
    await participant.publishData(data, { reliable });
  } catch (err) {
    logger.warn({ err, type }, 'Failed to publish data packet');
  }
}

async function publishAssistantStatus(
  room: Room,
  stage: string,
  details: Record<string, unknown> = {},
): Promise<void> {
  await publishPacket(room, 'assistant_status', { stage, ...details });
}

async function publishAssistantTranscript(
  room: Room,
  segmentId: string,
  transcript: string,
  details: Record<string, unknown> = {},
): Promise<void> {
  await publishPacket(room, 'assistant_transcript', {
    segmentId,
    transcript,
    ...details,
  });
}

async function publishAssistantResponse(
  room: Room,
  segmentId: string,
  text: string,
  details: Record<string, unknown> = {},
): Promise<void> {
  await publishPacket(room, 'assistant_response', {
    segmentId,
    text,
    ...details,
  });
}

async function publishAssistantError(
  room: Room,
  segmentId: string | undefined,
  message: string,
  details: Record<string, unknown> = {},
): Promise<void> {
  await publishPacket(room, 'assistant_error', {
    segmentId,
    message,
    ...details,
  });
}

async function main() {
  const env = loadEnv();
  const { url: serverUrl, token } = await createToken(env);

  const roomOptions: RoomOptions = {
    autoSubscribe: true,
    dynacast: true,
  };

  const room = new Room();
  await room.connect(serverUrl, token, roomOptions);

  logger.info('Worker connected to LiveKit');

  let idleTimer: NodeJS.Timeout | null = null;
  const scheduleIdleShutdown = () => {
    if (idleTimer) {
      clearTimeout(idleTimer);
      idleTimer = null;
    }
    if (room.remoteParticipants.size > 0) {
      return;
    }
    idleTimer = setTimeout(() => {
      if (room.remoteParticipants.size === 0) {
        logger.info(
          { timeoutMs: idleTimeoutMs },
          'No remote participants; shutting down worker',
        );
        room.disconnect().finally(() => {
          process.exit(0);
        });
      }
    }, idleTimeoutMs);
  };
  scheduleIdleShutdown();

  const projectId =
    process.env.GOOGLE_CLOUD_PROJECT ??
    process.env.GCP_PROJECT_ID ??
    process.env.GCP_PROJECT ??
    projectConfig.firebase.projectId ??
    null;

  if (!projectId) {
    throw new Error(
      'Missing GOOGLE_CLOUD_PROJECT (or GCP_PROJECT_ID) environment variable required for Google Cloud clients.',
    );
  }

  const sttLanguage = process.env.STT_LANGUAGE ?? workerDefaults.sttLanguage;
  const ttsLanguage =
    process.env.TTS_LANGUAGE ?? workerDefaults.ttsLanguage ?? sttLanguage;
  const ttsVoice = process.env.TTS_VOICE ?? workerDefaults.ttsVoice;
  const geminiModel = process.env.GEMINI_MODEL ?? workerDefaults.geminiModel;
  const geminiLocation =
    process.env.GEMINI_LOCATION ?? workerDefaults.geminiLocation;
  const systemPrompt =
    process.env.GEMINI_SYSTEM_PROMPT ?? workerDefaults.systemPrompt;
  const ttsSampleRate = Number.parseInt(
    process.env.TTS_SAMPLE_RATE ??
      (workerDefaults.ttsSampleRate?.toString() ?? '24000'),
    10,
  );
  const responseTrackName =
    process.env.RESPONSE_TRACK_NAME ??
    workerDefaults.responseTrackName ??
    'assistant';
  const ragTopK = Number.parseInt(
    process.env.VERTEX_SEARCH_TOP_K ??
      (projectConfig.vertexSearch?.topK?.toString() ?? '5'),
    10,
  );
  const parseNumericEnv = (value: string | undefined, fallback?: number) => {
    if (value == null) {
      return fallback;
    }
    const parsed = Number.parseInt(value, 10);
    return Number.isFinite(parsed) ? parsed : fallback;
  };
  const vadThreshold = parseNumericEnv(
    process.env.VAD_SPEECH_THRESHOLD,
    workerDefaults.vad?.speechThreshold,
  );
  const vadSilenceMs = parseNumericEnv(
    process.env.VAD_SILENCE_MS,
    workerDefaults.vad?.silenceMs,
  );
  const vadMinSpeechMs = parseNumericEnv(
    process.env.VAD_MIN_SPEECH_MS,
    workerDefaults.vad?.minSpeechMs,
  );
  const vadMaxSegmentMs = parseNumericEnv(
    process.env.VAD_MAX_SEGMENT_MS,
    workerDefaults.vad?.maxSegmentMs,
  );

  logger.info(
    {
      host: serverUrl,
      room: env.roomName,
      identity: env.participantIdentity,
      voice: ttsVoice,
      model: geminiModel,
    },
    'Connecting worker to LiveKit',
  );

  const responseSource = new AudioSource(ttsSampleRate, 1);
  const responseTrack = LocalAudioTrack.createAudioTrack(responseTrackName, responseSource);
  const publishOptions = new TrackPublishOptions({
    source: TrackSource.SOURCE_MICROPHONE,
    stream: responseTrackName,
  });

  if (room.localParticipant) {
    await room.localParticipant.publishTrack(responseTrack, publishOptions);
    logger.info('Assistant audio track published');
  } else {
    logger.warn('Local participant not available; assistant track not published');
  }
  await publishAssistantStatus(room, 'idle', {
    participant: env.participantIdentity,
  });

  const pipelineOptions: ConversationPipelineOptions = {
    responseSource,
    responseTrackName,
    sttLanguageCode: sttLanguage,
    ttsLanguageCode: ttsLanguage,
    ttsVoice,
    geminiModel,
    geminiLocation,
    ...(systemPrompt ? { systemPrompt } : {}),
    projectId,
    ttsSampleRate,
    ragTopK,
    onProgress: async (event) => {
      const segmentId = event.context.segmentId ?? randomUUID();
      const participant = event.context.participantIdentity ?? 'unknown';
      const baseDetails = {
        segmentId,
        participant,
        durationMs: event.metadata?.durationMs,
      };

      switch (event.stage) {
        case 'transcribing':
          await publishAssistantStatus(room, 'transcribing', {
            ...baseDetails,
            recordingDurationMs: event.metadata?.recordingDurationMs,
          });
          break;
        case 'transcribed': {
          const transcript = (event.metadata?.transcript as string | undefined)?.trim();
          if (transcript) {
            await publishAssistantTranscript(room, segmentId, transcript, {
              participant,
            });
          }
          await publishAssistantStatus(room, 'transcribed', {
            ...baseDetails,
            transcriptChars: transcript?.length ?? 0,
          });
          break;
        }
        case 'generating':
          await publishAssistantStatus(room, 'generating', {
            ...baseDetails,
            transcriptChars: event.metadata?.transcriptLength,
          });
          break;
        case 'generated': {
          const responseText = (event.metadata?.responseText as string | undefined) ?? '';
          if (responseText.trim().length > 0) {
            await publishAssistantResponse(room, segmentId, responseText.trim(), {
              participant,
            });
          }
          await publishAssistantStatus(room, 'generated', {
            ...baseDetails,
            responseChars: responseText.trim().length,
          });
          break;
        }
        case 'synthesizing':
          await publishAssistantStatus(room, 'synthesizing', {
            ...baseDetails,
            ttsSampleRate,
          });
          break;
        case 'speaking':
          await publishAssistantStatus(room, 'speaking', baseDetails);
          break;
        case 'completed':
          await publishAssistantStatus(room, 'completed', {
            ...baseDetails,
            totalDurationMs: event.metadata?.totalDurationMs,
            stages: event.metadata?.stages,
          });
          await publishAssistantStatus(room, 'idle', {
            ...baseDetails,
            totalDurationMs: event.metadata?.totalDurationMs,
          });
          break;
        case 'idle':
          await publishAssistantStatus(room, 'idle', {
            ...baseDetails,
            totalDurationMs: event.metadata?.totalDurationMs,
          });
          break;
        case 'skipped':
          await publishAssistantStatus(room, 'skipped', baseDetails);
          break;
        case 'error': {
          const message =
            (event.metadata?.errorMessage as string | undefined) ??
            'Conversation pipeline error';
          await publishAssistantError(room, segmentId, message, {
            participant,
          });
          await publishAssistantStatus(room, 'error', {
            ...baseDetails,
            error: message,
          });
          break;
        }
        default:
          await publishAssistantStatus(room, 'unknown', {
            ...baseDetails,
            stage: event.stage,
          });
          break;
      }
    },
  };
  const pipeline = new ConversationPipeline(pipelineOptions);
  logger.info(
    {
      vadThreshold,
      vadSilenceMs,
      vadMinSpeechMs,
      vadMaxSegmentMs,
    },
    'Voice activity detection configured',
  );

  const drainSink = (trackSid: string): void => {
    const entry = audioSinks.get(trackSid);
    if (!entry) {
      return;
    }
    audioSinks.delete(trackSid);
    void entry.sink
      .stop()
      .then((recording: AudioCaptureResult | null) => {
        if (!recording) {
          return;
        }
        const segmentId = randomUUID();
        void publishAssistantStatus(room, 'processing', {
          segmentId,
          participant: entry.participantIdentity ?? 'unknown',
          method: 'drain',
          durationMs: recording.durationMs,
          frames: recording.frameCount,
        });
        const participantIdentity = entry.participantIdentity ?? 'unknown';
        pipeline.processRecording(recording, {
          participantIdentity,
          segmentId,
          chatContext: participantContexts.get(participantIdentity) ?? undefined,
        });
      })
      .catch((err) => {
        logger.warn({ err, trackSid }, 'Failed to stop audio sink');
      });
  };

  room.on(RoomEvent.TrackPublished, (publication, participant) => {
    const trackSid = publication.sid;
    logger.info(
      {
        trackSid: trackSid ?? 'unknown',
        participant: participant.identity ?? 'unknown',
        kind: publication.kind,
      },
      'Remote participant published track',
    );
    if (publication.kind === TrackKind.KIND_AUDIO) {
      if (!trackSid) {
        logger.warn(
          { participant: participant.identity ?? 'unknown' },
          'Audio publication missing SID; cannot subscribe',
        );
        return;
      }
      try {
        publication.setSubscribed(true);
        logger.debug(
          { trackSid, participant: participant.identity ?? 'unknown' },
          'Subscribed to remote audio publication',
        );
      } catch (err) {
        logger.warn(
          { err, trackSid, participant: participant.identity ?? 'unknown' },
          'Failed to subscribe to remote audio publication',
        );
      }
    }
  });

  room.on(RoomEvent.TrackUnpublished, (publication, participant) => {
    const trackSid = publication.sid;
    logger.info(
      {
        trackSid: trackSid ?? 'unknown',
        participant: participant.identity ?? 'unknown',
        kind: publication.kind,
      },
      'Remote participant unpublished track',
    );
    if (publication.kind === TrackKind.KIND_AUDIO) {
      if (!trackSid) {
        return;
      }
      drainSink(trackSid);
    }
  });

  room.on(RoomEvent.DataReceived, (data, participant) => {
    const identity = participant?.identity ?? 'unknown';
    try {
      if (!data) {
        return;
      }
      let buffer: Buffer;
      if (Buffer.isBuffer(data)) {
        buffer = data;
      } else if (data instanceof ArrayBuffer) {
        buffer = Buffer.from(new Uint8Array(data));
      } else {
        const view = data as ArrayBufferView;
        buffer = Buffer.from(new Uint8Array(view.buffer));
      }
      const text = buffer.toString('utf8');
      const parsed = JSON.parse(text);
      if (parsed?.type === 'chat_context') {
        const payload = parsed.payload ?? {};
          const messages = Array.isArray(payload.messages)
            ? payload.messages
                .map((entry: any) => ({
                  role: typeof entry.role === 'string' ? entry.role : 'user',
                  text: typeof entry.text === 'string' ? entry.text : '',
                }))
                .filter((entry: { text: string }) => entry.text.length > 0)
            : [];
        participantContexts.set(identity, {
          chatId: typeof payload.chatId === 'string' ? payload.chatId : undefined,
          messages,
        });
        logger.debug(
          { identity, chatId: payload.chatId, messages: messages.length },
          'Chat context atualizado pelo cliente',
        );
        return;
      }
      if (parsed?.type === 'scene_event') {
        const payload = parsed.payload ?? {};
        const description = typeof payload.description === 'string'
          ? payload.description
          : '';
        const segmentId = randomUUID();
        const chatContext = participantContexts.get(identity);
        const scenePayload: any = {
          participantIdentity: identity,
          segmentId,
          description,
        };
        if (chatContext) {
          scenePayload.chatContext = chatContext;
        }
        pipeline.processSceneEvent(scenePayload);
        logger.info(
          {
            identity,
            descriptionLength: description.length,
          },
          'Scene event recebido do cliente',
        );
        return;
      }
    } catch (err) {
      logger.warn({ err }, 'Falha ao interpretar chat_context recebido');
    }
  });

  room.on(
    RoomEvent.TrackSubscribed,
    (track: RemoteTrack, publication: RemoteTrackPublication, participant) => {
      if (track.kind !== TrackKind.KIND_AUDIO) {
        return;
      }

      const trackSid = publication.sid;
      if (!trackSid) {
        logger.warn(
          { participant: participant.identity ?? 'unknown' },
          'Subscribed audio track missing SID; skipping sink attachment',
        );
        return;
      }

      const audioTrack = track as RemoteAudioTrack;
      drainSink(trackSid);

      const voiceActivity: any = {
        segmentIdFactory: () => randomUUID(),
        onSpeechStart: async (info: SpeechSegmentInfo) => {
          const participantIdentity = info.participantIdentity ?? 'unknown';
          await publishAssistantStatus(room, 'user_speaking', {
            segmentId: info.segmentId,
            participant: participantIdentity,
          });
        },
        onSegment: async (
          recording: AudioCaptureResult,
          info: SpeechSegmentInfo,
        ) => {
          await publishAssistantStatus(room, 'processing', {
            segmentId: info.segmentId,
            participant: info.participantIdentity ?? 'unknown',
            durationMs: recording.durationMs,
            frames: recording.frameCount,
          });
          const participantIdentity = info.participantIdentity ?? 'unknown';
          pipeline.processRecording(recording, {
            participantIdentity,
            segmentId: info.segmentId,
            chatContext: participantContexts.get(participantIdentity) ?? undefined,
          });
        },
      };
      if (vadThreshold !== undefined) voiceActivity.amplitudeThreshold = vadThreshold;
      if (vadSilenceMs !== undefined) voiceActivity.silenceDurationMs = vadSilenceMs;
      if (vadMinSpeechMs !== undefined) voiceActivity.minSpeechMs = vadMinSpeechMs;
      if (vadMaxSegmentMs !== undefined) voiceActivity.maxSegmentMs = vadMaxSegmentMs;

      const sink = createAudioSink(audioTrack, {
        participantIdentity: participant.identity,
        publicationSid: trackSid,
      }, {
        voiceActivity,
      });
      audioSinks.set(trackSid, {
        sink,
        participantIdentity: participant.identity,
      });

      void publishAssistantStatus(room, 'listening', {
        trackSid,
        participant: participant.identity ?? 'unknown',
      });

      logger.info(
        {
          trackSid,
          participant: participant.identity ?? 'unknown',
        },
        'Audio track subscribed and sink attached',
      );
    },
  );

  room.on(
    RoomEvent.TrackUnsubscribed,
    (track: RemoteTrack, publication: RemoteTrackPublication) => {
      if (track.kind !== TrackKind.KIND_AUDIO) {
        return;
      }
      const trackSid = publication.sid;
      if (!trackSid) {
        return;
      }
      drainSink(trackSid);
      logger.info({ trackSid }, 'Audio track unsubscribed');
    },
  );

  room.on(RoomEvent.ParticipantConnected, (participant) => {
    logger.info({ identity: participant.identity ?? 'unknown' }, 'Participant connected');
    scheduleIdleShutdown();
  });

  room.on(RoomEvent.ParticipantDisconnected, (participant) => {
    logger.info({ identity: participant.identity ?? 'unknown' }, 'Participant disconnected');
    const affected = Array.from(audioSinks.entries()).filter(
      ([, entry]) => entry.participantIdentity === participant.identity,
    );
    for (const [trackSid] of affected) {
      drainSink(trackSid);
    }
    if (participant.identity) {
      participantContexts.delete(participant.identity);
    }
    scheduleIdleShutdown();
  });

  room.on(RoomEvent.Disconnected, (reason) => {
    logger.warn({ reason }, 'Disconnected from LiveKit room');
    process.exit(0);
  });
}

main().catch((error) => {
  logger.error(error, 'Worker failed');
  process.exit(1);
});



