import { existsSync, readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

export interface ProjectConfig {
  firebase: {
    projectId: string;
    functionsRegion: string;
    useFunctionsEmulator?: boolean;
  };
  appCheck: {
    reCaptchaV3SiteKey: string;
  };
  livekit: {
    host: string;
    apiKey: string;
    apiSecret: string;
    defaultRoom: string;
    tokenFunctionName: string;
    tokenTtlSeconds?: number;
  };
  worker: {
    defaultIdentity: string;
    responseTrackName?: string;
    sttLanguage: string;
    ttsLanguage?: string;
    ttsVoice: string;
    ttsSampleRate?: number;
    geminiModel: string;
    geminiLocation: string;
    googleApplicationCredentials?: string;
    systemPrompt?: string;
    vad?: {
      speechThreshold?: number;
      silenceMs?: number;
      minSpeechMs?: number;
      maxSegmentMs?: number;
    };
  };
  vertexSearch?: {
    projectId?: string;
    location?: string;
    appId?: string;
    dataStoreId?: string;
    topK?: number;
  };
}

function loadProjectConfig(): ProjectConfig {
  const __filename = fileURLToPath(import.meta.url);
  const __dirname = dirname(__filename);
  const candidates = [
    process.env.PROJECT_CONFIG_PATH,
    resolve(__dirname, '../../../config/project_config.json'),
    resolve(__dirname, '../../config/project_config.json'),
    resolve(process.cwd(), 'config/project_config.json'),
  ].filter(Boolean) as string[];

  const configPath = candidates.find((candidate) => existsSync(candidate));
  if (!configPath) {
    throw new Error(
      `project_config.json not found. Tried: ${candidates.join(', ')}`,
    );
  }

  const buffer = readFileSync(configPath, 'utf8');
  return JSON.parse(buffer) as ProjectConfig;
}

const projectConfig = loadProjectConfig();
export default projectConfig;
