import pino from "pino";
import { AudioFrame, AudioSource } from "@livekit/rtc-node";
import { SpeechClient } from "@google-cloud/speech";
import { TextToSpeechClient } from "@google-cloud/text-to-speech";
import { VertexAI } from "@google-cloud/vertexai";
import { SearchServiceClient, protos } from "@google-cloud/discoveryengine";
import { randomUUID } from "node:crypto";
import type { AudioCaptureResult } from "../livekit/audioSink.js";
import projectConfig from "../shared/project_config.js";

export type ConversationStage =
  | "transcribing"
  | "transcribed"
  | "generating"
  | "generated"
  | "synthesizing"
  | "speaking"
  | "completed"
  | "skipped"
  | "error"
  | "idle";

export type ConversationChatMessage = {
  role: string;
  text: string;
};

export interface ChatContextPayload {
  chatId?: string;
  messages?: ConversationChatMessage[];
}

export interface SceneEventPayload {
  participantIdentity: string;
  segmentId?: string;
  description: string;
  chatContext?: ChatContextPayload | undefined;
}

export interface ConversationPipelineOptions {
  responseSource: AudioSource;
  responseTrackName?: string;
  sttLanguageCode: string;
  ttsLanguageCode: string;
  ttsVoice: string;
  geminiModel: string;
  geminiLocation: string;
  projectId: string;
  ttsSampleRate: number;
  ttsAudioEncoding?: "LINEAR16" | "MP3" | "OGG_OPUS";
  systemPrompt?: string;
  onProgress?: (event: ConversationProgressEvent) => void | Promise<void>;
  ragTopK?: number;
}

interface ConversationContext {
  participantIdentity: string;
  segmentId?: string;
  source?: string;
  chatContext?: ChatContextPayload | undefined;
}

export interface ConversationProgressEvent {
  stage: ConversationStage;
  context: ConversationContext;
  metadata?: Record<string, unknown>;
}

const logger = pino({ name: "conversation-pipeline" });

export class ConversationPipeline {
  private readonly responseSource: AudioSource;
  private readonly speechClient: SpeechClient;
  private readonly ttsClient: TextToSpeechClient;
  private readonly vertex: VertexAI;
  private readonly searchClient: SearchServiceClient | null;
  private readonly options: ConversationPipelineOptions;
  private readonly progressHandler?: ConversationPipelineOptions["onProgress"];
  private publishQueue: Promise<void> = Promise.resolve();
  private readonly servingConfigPath: string | null;
  private readonly ragTopK: number;
  private readonly maxBufferedChars = 240;

  constructor(options: ConversationPipelineOptions) {
    this.options = options;
    this.responseSource = options.responseSource;
    this.speechClient = new SpeechClient();
    this.ttsClient = new TextToSpeechClient();
    this.vertex = new VertexAI({
      project: options.projectId,
      location: options.geminiLocation,
    });
    this.progressHandler = options.onProgress;

    const searchCfg = projectConfig.vertexSearch;
    const project = searchCfg?.projectId ?? options.projectId;
    const location = searchCfg?.location ?? "global";
    const dataStoreId = searchCfg?.dataStoreId;
    this.servingConfigPath = project && location && dataStoreId
      ? [
          "projects",
          project,
          "locations",
          location,
          "collections",
          "default_collection",
          "dataStores",
          dataStoreId,
          "servingConfigs",
          "default_serving_config",
        ].join("/")
      : null;
    const apiEndpoint = location === "global"
      ? undefined
      : `${location}-discoveryengine.googleapis.com`;
    this.searchClient = this.servingConfigPath
      ? new SearchServiceClient(apiEndpoint ? { apiEndpoint } : {})
      : null;
    this.ragTopK = options.ragTopK ?? searchCfg?.topK ?? 5;
  }

  private async emitProgress(
    stage: ConversationStage,
    context: ConversationContext,
    metadata: Record<string, unknown> = {},
  ): Promise<void> {
    if (!this.progressHandler) {
      return;
    }
    try {
      await this.progressHandler({
        stage,
        context,
        metadata,
      });
    } catch (err) {
      logger.warn({ err, stage, segmentId: context.segmentId }, "Progress handler failed");
    }
  }

  processRecording(recording: AudioCaptureResult, context: ConversationContext): void {
    this.publishQueue = this.publishQueue
      .then(() => this.handleRecording(recording, context))
      .catch((err) => {
        logger.error({ err }, "Conversation pipeline failed");
      });
  }

  processSceneEvent(event: SceneEventPayload): void {
    const context: ConversationContext = {
      participantIdentity: event.participantIdentity,
      segmentId: event.segmentId ?? randomUUID(),
      source: "scene_event",
      chatContext: event.chatContext,
    };

    this.publishQueue = this.publishQueue
      .then(() => this.handleSceneEvent(event, context))
      .catch((err) => {
        logger.error({ err }, "Scene event pipeline failed");
      });
  }

  private async handleRecording(
    recording: AudioCaptureResult,
    context: ConversationContext,
  ): Promise<void> {
    try {
      const startedAt = Date.now();
      logger.info(
        {
          participant: context.participantIdentity,
          segmentId: context.segmentId,
          durationMs: recording.durationMs,
          sampleRate: recording.sampleRate,
          channels: recording.channels,
          frameCount: recording.frameCount,
        },
        "Processing recording",
      );

      await this.emitProgress("transcribing", context, {
        recordingDurationMs: recording.durationMs,
      });
      const transcriptionStartedAt = Date.now();
      const transcript = await this.transcribe(recording);
      const transcriptionMs = Date.now() - transcriptionStartedAt;
      if (!transcript) {
        logger.info(
          {
            participant: context.participantIdentity,
            segmentId: context.segmentId,
            transcriptionMs,
          },
          "No transcript returned, skipping AI response.",
        );
        await this.emitProgress("skipped", context, {
          reason: "empty_transcript",
          transcriptionMs,
        });
        return;
      }

      logger.info(
        {
          participant: context.participantIdentity,
          segmentId: context.segmentId,
          transcript,
          transcriptionMs,
        },
        "Transcription complete",
      );
      await this.emitProgress("transcribed", context, {
        transcript,
        transcriptionMs,
      });

      const history = context.chatContext?.messages ?? [];
      await this.emitProgress("generating", context, {
        transcriptLength: transcript.length,
      });

      const streamed = await this.generateAndStreamResponse({
        userText: transcript,
        participantIdentity: context.participantIdentity,
        history,
        context,
      });
      if (!streamed) {
        await this.emitProgress("skipped", context, {
          reason: "empty_response",
          transcript,
        });
        return;
      }

      const totalDurationMs = Date.now() - startedAt;
      logger.info(
        {
          participant: context.participantIdentity,
          segmentId: context.segmentId,
          totalDurationMs,
          streaming: {
            generationMs: streamed.generationMs,
            synthesisMs: streamed.synthesisMs,
            playbackMs: streamed.playbackMs,
          },
        },
        "Audio response streamed",
      );
      await this.emitProgress("completed", context, {
        totalDurationMs,
        stages: {
          transcriptionMs,
          generationMs: streamed.generationMs,
          synthesisMs: streamed.synthesisMs,
          playbackMs: streamed.playbackMs,
        },
      });
    } catch (err) {
      const message =
        err instanceof Error ? err.message : "Unknown pipeline error";
      logger.error(
        {
          err,
          participant: context.participantIdentity,
          segmentId: context.segmentId,
        },
        "Failed to process recording",
      );
      await this.emitProgress("error", context, {
        errorMessage: message,
      });
    }
  }

  private async transcribe(recording: AudioCaptureResult): Promise<string> {
    const request = {
      config: {
        encoding: "LINEAR16" as const,
        sampleRateHertz: recording.sampleRate,
        languageCode: this.options.sttLanguageCode,
        audioChannelCount: recording.channels,
        enableAutomaticPunctuation: true,
      },
      audio: {
        content: recording.pcm.toString("base64"),
      },
    };

    const [response] = await this.speechClient.recognize(request);
    const transcript =
      response.results
        ?.map((result) => result.alternatives?.[0]?.transcript ?? "")
        .join(" ")
        .trim() ?? "";
    return transcript;
  }

  private async handleSceneEvent(event: SceneEventPayload, context: ConversationContext): Promise<void> {
    try {
      const startedAt = Date.now();
      logger.info(
        {
          participant: context.participantIdentity,
          segmentId: context.segmentId,
          descriptionLength: event.description.length,
        },
        "Processing scene event",
      );

      await this.emitProgress("generating", context, {
        descriptionLength: event.description.length,
      });

      const history = event.chatContext?.messages ?? [];
      const streamed = await this.generateAndStreamResponse({
        userText: event.description,
        participantIdentity: context.participantIdentity,
        history,
        context,
      });
      if (!streamed) {
        await this.emitProgress("skipped", context, {
          reason: "empty_scene_response",
        });
        return;
      }

      const totalDurationMs = Date.now() - startedAt;
      await this.emitProgress("completed", context, {
        totalDurationMs,
        stages: {
          generationMs: streamed.generationMs,
          synthesisMs: streamed.synthesisMs,
          playbackMs: streamed.playbackMs,
        },
      });
      await this.emitProgress("idle", context, {
        totalDurationMs,
      });
    } catch (err) {
      const message = err instanceof Error ? err.message : "Unknown scene pipeline error";
      logger.error(
        {
          err,
          participant: context.participantIdentity,
          segmentId: context.segmentId,
        },
        "Failed to process scene event",
      );
      await this.emitProgress("error", context, {
        errorMessage: message,
      });
    }
  }

  private async generateModelResponse(input: {
    userText: string;
    participantIdentity: string;
    history: ConversationChatMessage[];
    ragResults?: RagSearchResult[] | undefined;
  }): Promise<string> {
    // Legacy (non-streaming) path retained for fallback.
    const model = this.vertex.getGenerativeModel({
      model: this.options.geminiModel,
    });

    const systemPrompt =
      this.options.systemPrompt ??
      "Voce e um assistente de voz prestativo. Responda de forma objetiva em portugues do Brasil.";

    const trimmedHistory = input.history.slice(-120);
    const normalize = (text: string) => {
      const maxChars = 1200;
      if (text.length <= maxChars) return text;
      return text.substring(0, maxChars);
    };
    const historyText = trimmedHistory
        .map((entry) => {
          const role = entry.role === 'assistant'
              ? 'Assistente'
              : entry.role === 'system'
                  ? 'Contexto'
                  : 'Usuario';
          return `${role}: ${normalize(entry.text)}`;
        })
        .join("\n");
    const ragSection = (input.ragResults && input.ragResults.length)
      ? input.ragResults
          .map((r, idx) => {
            const title = r.title ?? `Fonte ${idx + 1}`;
            const snippet = normalize(r.snippet ?? "");
            const uri = r.uri ? ` (${r.uri})` : "";
            return `[${idx + 1}] ${title}${uri}\n${snippet}`;
          })
          .join("\n\n")
      : "";
    const currentLine = `Usuario (${input.participantIdentity}): ${input.userText}`;
    const composedPrompt = [
      systemPrompt,
      ragSection ? `\nInformacoes de apoio (RAG):\n${ragSection}` : "",
      historyText.length > 0 ? `\nHistorico:\n${historyText}` : "",
      `\n${currentLine}`,
    ].join("\n");

    const parts: Array<{ text?: string | undefined }> = [
      { text: composedPrompt },
    ];

    const result = await model.generateContent({
      contents: [
        {
          role: "user",
          parts: parts as any, // Part typing is permissive; cast to satisfy strict optional checks
        },
      ],
    });

    const candidate = result.response?.candidates?.[0];
    const text =
      candidate?.content?.parts
        ?.map((part) => part.text ?? "")
        .join(" ")
        .trim() ?? "";
    return text;
  }

  private buildPromptParts(input: {
    userText: string;
    participantIdentity: string;
    history: ConversationChatMessage[];
    ragResults?: RagSearchResult[] | undefined;
  }): Array<{ text?: string }> {
    const systemPrompt =
      this.options.systemPrompt ??
      "Voce e um assistente de voz prestativo. Responda de forma objetiva em portugues do Brasil.";

    const trimmedHistory = input.history.slice(-120);
    const normalize = (text: string) => {
      const maxChars = 1200;
      if (text.length <= maxChars) return text;
      return text.substring(0, maxChars);
    };
    const historyText = trimmedHistory
        .map((entry) => {
          const role = entry.role === 'assistant'
              ? 'Assistente'
              : entry.role === 'system'
                  ? 'Contexto'
                  : 'Usuario';
          return `${role}: ${normalize(entry.text)}`;
        })
        .join("\n");
    const ragSection = (input.ragResults && input.ragResults.length)
      ? input.ragResults
          .map((r, idx) => {
            const title = r.title ?? `Fonte ${idx + 1}`;
            const snippet = normalize(r.snippet ?? "");
            const uri = r.uri ? ` (${r.uri})` : "";
            return `[${idx + 1}] ${title}${uri}\n${snippet}`;
          })
          .join("\n\n")
      : "";
    const currentLine = `Usuario (${input.participantIdentity}): ${input.userText}`;
    const composedPrompt = [
      systemPrompt,
      ragSection ? `\nInformacoes de apoio (RAG):\n${ragSection}` : "",
      historyText.length > 0 ? `\nHistorico:\n${historyText}` : "",
      `\n${currentLine}`,
    ].join("\n");

    return [{ text: composedPrompt }];
  }

  private async synthesizeSpeech(text: string): Promise<Buffer | null> {
    const [response] = await this.ttsClient.synthesizeSpeech({
      input: { text },
      voice: {
        languageCode: this.options.ttsLanguageCode,
        name: this.options.ttsVoice,
      },
      audioConfig: {
        audioEncoding: this.options.ttsAudioEncoding ?? "LINEAR16",
        sampleRateHertz: this.options.ttsSampleRate,
        speakingRate: 1.0,
      },
    });

    const audioContent = response.audioContent;
    if (!audioContent || audioContent.length === 0) {
      return null;
    }

    if (audioContent instanceof Uint8Array) {
      return Buffer.from(audioContent);
    }

    if (typeof audioContent === "string") {
      return Buffer.from(audioContent, "base64");
    }

    logger.warn('Unsupported audioContent payload type from TTS');
    return null;
  }

  private async playResponse(buffer: Buffer, context: ConversationContext): Promise<void> {
    const int16 = new Int16Array(buffer.buffer, buffer.byteOffset, Math.floor(buffer.length / 2));
    const sampleRate = this.options.ttsSampleRate;
    const channels = 1;
    const samplesPerFrame = Math.floor((sampleRate / 1000) * 20);

    for (let offset = 0; offset < int16.length; offset += samplesPerFrame) {
      const chunk = int16.subarray(offset, Math.min(offset + samplesPerFrame, int16.length));
      const frameData = new Int16Array(chunk.length);
      frameData.set(chunk);
      const frame = new AudioFrame(frameData, sampleRate, channels, Math.floor(chunk.length / channels));
      await this.responseSource.captureFrame(frame);
    }

    await this.responseSource.waitForPlayout();
  }

  private async searchRag(query: string): Promise<RagSearchResult[]> {
    if (!this.searchClient || !this.servingConfigPath) {
      return [];
    }
    const pageSize = Math.min(Math.max(this.ragTopK, 1), 10);
    const request: protos.google.cloud.discoveryengine.v1.ISearchRequest = {
      servingConfig: this.servingConfigPath,
      query,
      pageSize,
      queryExpansionSpec: { condition: protos.google.cloud.discoveryengine.v1.SearchRequest.QueryExpansionSpec.Condition.AUTO },
      spellCorrectionSpec: { mode: protos.google.cloud.discoveryengine.v1.SearchRequest.SpellCorrectionSpec.Mode.AUTO },
    };
    const results: RagSearchResult[] = [];
    const iterable = this.searchClient.searchAsync(request);
    for await (const result of iterable) {
      const document = result.document as any;
      const derived = (document?.derivedStructData as Record<string, unknown> | undefined) ?? {};
      const struct = (document?.structData as Record<string, unknown> | undefined) ?? {};
      const extractiveAnswers = Array.isArray((derived as any)?.extractive_answers)
        ? (derived as any).extractive_answers
        : Array.isArray((derived as any)?.extractive_answer)
        ? (derived as any).extractive_answer
        : [];
      const snippets: string[] = [];
      for (const answer of extractiveAnswers) {
        if (typeof answer?.content === "string") {
          snippets.push(answer.content);
        }
      }
      const fallbackSnippet =
        typeof (derived as any)?.snippet === "string"
          ? (derived as any).snippet
          : typeof (struct as any)?.content === "string"
          ? (struct as any).content
          : undefined;
      results.push({
        id: document?.id ?? document?.name ?? null,
        uri: document?.uri ?? (struct as any)?.uri ?? null,
        title: document?.title ?? (struct as any)?.title ?? (struct as any)?.file_name ?? null,
        snippet: snippets.join(" ").trim() || fallbackSnippet,
        score: typeof (result as any)?.modelScore === "number" ? (result as any).modelScore : undefined,
      });
    }
    return results;
  }

  private splitFlushableSentences(
    buffer: string,
    minChars = 24,
    maxBuffer?: number,
  ): { ready: string[]; remaining: string } {
    const effectiveMax = maxBuffer ?? this.maxBufferedChars;
    const ready: string[] = [];
    let working = buffer;
    const sentenceEndRegex = /[.!?]/;
    while (true) {
      const matchIndex = working.search(sentenceEndRegex);
      if (matchIndex === -1) {
        break;
      }
      const cut = matchIndex + 1;
      const candidate = working.slice(0, cut).trim();
      working = working.slice(cut);
      if (candidate.length >= minChars || working.length > effectiveMax) {
        ready.push(candidate);
      } else {
        // If too short, keep accumulating.
        working = `${candidate} ${working}`.trim();
        break;
      }
    }
    if (working.length > effectiveMax) {
      ready.push(working.trim());
      working = "";
    }
    return {
      ready: ready.filter((r) => r.length > 0),
      remaining: working,
    };
  }

  private async generateAndStreamResponse(input: {
    userText: string;
    participantIdentity: string;
    history: ConversationChatMessage[];
    context: ConversationContext;
  }): Promise<{
    text: string;
    generationMs: number;
    synthesisMs: number;
    playbackMs: number;
  } | null> {
    const context = input.context;

    let ragResults: RagSearchResult[] | undefined;
    try {
      ragResults = await this.searchRag(input.userText);
    } catch (err) {
      logger.warn({ err }, "RAG search failed, continuing without context");
    }

    const promptParts = this.buildPromptParts({
      userText: input.userText,
      participantIdentity: input.participantIdentity,
      history: input.history,
      ragResults,
    });

    const model = this.vertex.getGenerativeModel({
      model: this.options.geminiModel,
    });

    const streamResult = await model.generateContentStream({
      contents: [
        {
          role: "user",
          parts: promptParts as any,
        },
      ],
    });

    const generationStartedAt = Date.now();
    let generationMs = 0;
    let synthesisMs = 0;
    let playbackMs = 0;
    let aggregatedText = "";
    let buffered = "";
    let firstTts = true;
    let playbackQueue: Promise<void> = Promise.resolve();

    const enqueueTts = (textChunk: string) => {
      if (!textChunk.trim()) {
        return;
      }
      playbackQueue = playbackQueue.then(async () => {
        if (firstTts) {
          await this.emitProgress("synthesizing", context, {
            responseLength: aggregatedText.length,
            partial: true,
          });
          firstTts = false;
        }
        const ttsStart = Date.now();
        const audioBuffer = await this.synthesizeSpeech(textChunk);
        synthesisMs += Date.now() - ttsStart;
        if (!audioBuffer) {
          return;
        }
        const playStart = Date.now();
        await this.playResponse(audioBuffer, context);
        playbackMs += Date.now() - playStart;
        await this.emitProgress("speaking", context, {
          partial: true,
          chunkChars: textChunk.length,
          audioBytes: audioBuffer.length,
        });
      });
    };

    try {
      for await (const item of streamResult.stream) {
        const parts = item.candidates?.[0]?.content?.parts ?? [];
        for (const part of parts) {
          if (!part.text) continue;
          aggregatedText += part.text;
          buffered += part.text;
          const flushed = this.splitFlushableSentences(buffered);
          flushed.ready.forEach(enqueueTts);
          buffered = flushed.remaining;
        }
      }
      if (buffered.trim().length) {
        enqueueTts(buffered.trim());
        buffered = "";
      }
      generationMs = Date.now() - generationStartedAt;
    } catch (err) {
      logger.error({ err }, "Streaming generation failed");
      return null;
    }

    const finalText = aggregatedText.trim();
    if (!finalText.length) {
      return null;
    }

    await this.emitProgress("generated", context, {
      responseText: finalText,
      generationMs,
    });

    await playbackQueue;

    return {
      text: finalText,
      generationMs,
      synthesisMs,
      playbackMs,
    };
  }
}

type RagSearchResult = {
  id?: string | null;
  uri?: string | null;
  title?: string | null;
  snippet?: string;
  score?: number;
};
