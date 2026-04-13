import pino from 'pino';
import { randomUUID } from 'node:crypto';
import { AudioStream } from '@livekit/rtc-node';
import type { RemoteAudioTrack } from '@livekit/rtc-node';
import type { AudioFrame } from '@livekit/rtc-node';
import projectConfig from '../shared/project_config.js';

const logger = pino({
  name: 'audio-sink',
  level: process.env.WORKER_AUDIO_LOG_LEVEL ?? 'info',
});

export interface AudioCaptureResult {
  pcm: Buffer;
  sampleRate: number;
  channels: number;
  durationMs: number;
  frameCount: number;
}

export interface AudioSink {
  stop: () => Promise<AudioCaptureResult | null>;
}

export interface SpeechSegmentInfo {
  segmentId: string;
  participantIdentity?: string | undefined;
  trackSid: string;
  startedAt: number;
  durationMs: number;
  frameCount: number;
}

export interface VoiceActivityOptions {
  /**
   * Root mean square threshold that marks a frame as speech.
   * Typical PCM amplitude ranges from 0 - 32767.
   */
  amplitudeThreshold?: number;
  /**
   * Milliseconds of silence required to consider the speech finished.
   */
  silenceDurationMs?: number;
  /**
   * Minimum speech length (in milliseconds) before emitting a segment.
   */
  minSpeechMs?: number;
  /**
   * Maximum segment duration to avoid unbounded buffers.
   */
  maxSegmentMs?: number;
  /**
   * Optional factory to generate custom segment identifiers.
   */
  segmentIdFactory?: () => string;
  /**
   * Invoked when a new speech segment is detected.
   */
  onSpeechStart?: (info: SpeechSegmentInfo) => void | Promise<void>;
  /**
   * Invoked when a speech segment is finished (silence detected or max length reached).
   */
  onSegment?: (
    recording: AudioCaptureResult,
    info: SpeechSegmentInfo,
  ) => void | Promise<void>;
}

export interface AudioSinkOptions {
  voiceActivity?: VoiceActivityOptions;
}

export function createAudioSink(
  track: RemoteAudioTrack,
  context: { participantIdentity?: string; publicationSid: string },
  options?: AudioSinkOptions,
): AudioSink {
  const stream = new AudioStream(track);
  const reader = stream.getReader();
  let cancelled = false;
  const frames: Int16Array[] = [];
  let sampleRate = 0;
  let channels = 0;
  let frameCount = 0;

  const voiceOptions = options?.voiceActivity;
  const vadDefaults = projectConfig.worker.vad ?? {};
  const vadThreshold = voiceOptions?.amplitudeThreshold ??
      vadDefaults.speechThreshold ?? 1100;
  const vadSilenceMs = voiceOptions?.silenceDurationMs ??
      vadDefaults.silenceMs ?? 500;
  const vadMinSpeechMs = voiceOptions?.minSpeechMs ??
      vadDefaults.minSpeechMs ?? 350;
  const vadMaxSegmentMs = voiceOptions?.maxSegmentMs ??
      vadDefaults.maxSegmentMs ?? 15000;

  interface PendingSegment {
    id: string;
    frames: Int16Array[];
    sampleRate: number;
    channels: number;
    frameCount: number;
    startedAt: number;
    durationMs: number;
    lastSpeechAt: number;
  }

  let pendingSegment: PendingSegment | null = null;
  let segmentQueue: Promise<void> = Promise.resolve();

  const resetPendingSegment = (): void => {
    pendingSegment = null;
  };

  const computeFrameDurationMs = (frame: AudioFrame): number => {
    if (frame.sampleRate === 0 || frame.channels === 0) {
      return 0;
    }
    return (frame.samplesPerChannel / frame.sampleRate) * 1000;
  };

  const calculateRms = (data: Int16Array): number => {
    if (!data.length) {
      return 0;
    }
    let sumSquares = 0;
    for (let i = 0; i < data.length; i += 1) {
      const sample = data[i];
      if (sample === undefined) {
        continue;
      }
      sumSquares += sample * sample;
    }
    return Math.sqrt(sumSquares / data.length);
  };

  const toCaptureResult = (
    segment: PendingSegment,
  ): AudioCaptureResult => {
    const totalSamples = segment.frames.reduce(
      (acc, frame) => acc + frame.length,
      0,
    );
    const int16 = new Int16Array(totalSamples);
    let offset = 0;
    for (const frame of segment.frames) {
      int16.set(frame, offset);
      offset += frame.length;
    }
    const pcm = Buffer.from(int16.buffer);
    return {
      pcm,
      sampleRate: segment.sampleRate,
      channels: segment.channels,
      durationMs: segment.durationMs,
      frameCount: segment.frameCount,
    };
  };

  const emitSegment = (
    segment: PendingSegment,
    reason: 'silence' | 'maxDuration' | 'stop',
  ): void => {
    if (!voiceOptions?.onSegment) {
      return;
    }
    if (segment.durationMs < vadMinSpeechMs || segment.frameCount === 0) {
      logger.debug(
        {
          trackSid: context.publicationSid,
          reason,
          durationMs: segment.durationMs,
          frames: segment.frameCount,
        },
        'Discarding short speech segment',
      );
      return;
    }

    const captureResult = toCaptureResult(segment);
    const info: SpeechSegmentInfo = {
      segmentId: segment.id,
      participantIdentity: context.participantIdentity,
      trackSid: context.publicationSid,
      startedAt: segment.startedAt,
      durationMs: captureResult.durationMs,
      frameCount: captureResult.frameCount,
    };

    segmentQueue = segmentQueue.then(async () => {
      try {
        await voiceOptions.onSegment?.(captureResult, info);
      } catch (err) {
        logger.error(
          { err, trackSid: context.publicationSid, segmentId: info.segmentId },
          'Voice segment callback failed',
        );
      }
    });
  };

  const ensureSegment = (frameDurationMs: number): PendingSegment => {
    if (pendingSegment) {
      return pendingSegment;
    }
    const newSegment: PendingSegment = {
      id: voiceOptions?.segmentIdFactory?.() ?? randomUUID(),
      frames: [],
      sampleRate,
      channels,
      frameCount: 0,
      startedAt: Date.now(),
      durationMs: 0,
      lastSpeechAt: Date.now(),
    };
    pendingSegment = newSegment;
    const info: SpeechSegmentInfo = {
      segmentId: newSegment.id,
      participantIdentity: context.participantIdentity,
      trackSid: context.publicationSid,
      startedAt: newSegment.startedAt,
      durationMs: 0,
      frameCount: 0,
    };
    segmentQueue = segmentQueue.then(async () => {
      try {
        await voiceOptions?.onSpeechStart?.(info);
      } catch (err) {
        logger.warn(
          { err, trackSid: context.publicationSid, segmentId: info.segmentId },
          'Speech start callback failed',
        );
      }
    });
    return newSegment;
  };

  const handleVoiceActivity = (frame: AudioFrame): void => {
    if (!voiceOptions) {
      return;
    }
    const frameDurationMs = computeFrameDurationMs(frame);
    const rms = calculateRms(frame.data);
    const now = Date.now();
    const isSpeech = rms >= vadThreshold;

    if (isSpeech) {
      const segment = ensureSegment(frameDurationMs);
      segment.frames.push(frame.data.slice());
      segment.sampleRate = frame.sampleRate;
      segment.channels = frame.channels;
      segment.frameCount += 1;
      segment.durationMs += frameDurationMs;
      segment.lastSpeechAt = now;

      if (segment.durationMs >= vadMaxSegmentMs) {
        logger.info(
          {
            trackSid: context.publicationSid,
            durationMs: segment.durationMs,
            frames: segment.frameCount,
          },
          'Voice segment reached max duration, flushing',
        );
        emitSegment(segment, 'maxDuration');
        resetPendingSegment();
      }
      return;
    }

    if (pendingSegment) {
      pendingSegment.durationMs += frameDurationMs;
      pendingSegment.frameCount += 1;
      pendingSegment.frames.push(frame.data.slice());
      if (now - pendingSegment.lastSpeechAt >= vadSilenceMs) {
        emitSegment(pendingSegment, 'silence');
        resetPendingSegment();
      }
    }
  };

  logger.info(
    {
      trackSid: context.publicationSid,
      participant: context.participantIdentity,
    },
    'Audio stream reader attached',
  );

  (async () => {
    try {
      while (!cancelled) {
        const { value, done } = await reader.read();
        if (done || value == null) {
          break;
        }
        const frameValue = value;
        frameCount += 1;
        sampleRate = frameValue.sampleRate;
        channels = frameValue.channels;
        frames.push(frameValue.data.slice());
        logger.debug(
          {
            trackSid: context.publicationSid,
            sampleRate: frameValue.sampleRate,
            channels: frameValue.channels,
            samplesPerChannel: frameValue.samplesPerChannel,
          },
          'Captured audio frame',
        );
        handleVoiceActivity(frameValue);
      }
    } catch (err) {
      logger.error({ err, trackSid: context.publicationSid }, 'Error while reading audio stream');
    } finally {
      logger.info({ trackSid: context.publicationSid }, 'Audio stream reader finished');
    }
  })();

  return {
    stop: async () => {
      cancelled = true;
      try {
        await reader.cancel();
      } catch (err) {
        logger.warn({ err, trackSid: context.publicationSid }, 'Failed to cancel audio stream reader');
      }
      if (!frames.length || sampleRate === 0) {
        return null;
      }

      if (pendingSegment) {
        emitSegment(pendingSegment, 'stop');
        resetPendingSegment();
      }

      const totalSamples = frames.reduce((acc, frame) => acc + frame.length, 0);
      const int16 = new Int16Array(totalSamples);
      let offset = 0;
      for (const frame of frames) {
        int16.set(frame, offset);
        offset += frame.length;
      }
      const pcm = Buffer.from(int16.buffer);
      const durationMs = (totalSamples / channels / sampleRate) * 1000;

      logger.info(
        {
          trackSid: context.publicationSid,
          frames: frameCount,
          sampleRate,
          channels,
          durationMs,
        },
        'Audio sink stopped',
      );

      return {
        pcm,
        sampleRate,
        channels,
        durationMs,
        frameCount,
      };
    },
  };
}
