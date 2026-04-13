import cors from 'cors';
import type { Request, Response } from 'express';
import * as admin from 'firebase-admin';
import * as functions from 'firebase-functions/v1';
import { AccessToken } from 'livekit-server-sdk';
import { SearchServiceClient } from '@google-cloud/discoveryengine';
import { GoogleAuth } from 'google-auth-library';
import projectConfig from './config/project_config.json';

admin.initializeApp();

const firebaseProjectId = projectConfig.firebase.projectId;
const firebaseFunctionsRegion = projectConfig.firebase.functionsRegion;
const corsHandler = cors({
  origin: true,
  methods: ['POST', 'OPTIONS'],
  allowedHeaders: ['Authorization', 'Content-Type', 'X-Firebase-AppCheck'],
});

const APP_CHECK_HEADER = 'x-firebase-appcheck';
const AUTHORIZATION_HEADER = 'authorization';

const runtimeConfig = functions.config() as {
  livekit?: {
    host?: string;
    api_key?: string;
    api_secret?: string;
    default_room?: string;
    token_ttl_seconds?: number;
  };
  vertexsearch?: {
    project_id?: string;
    location?: string;
    app_id?: string;
    data_store_id?: string;
    top_k?: string;
  };
  workerjob?: {
    project_id?: string;
    region?: string;
    job_name?: string;
  };
};

const LIVEKIT_HOST =
  process.env.LIVEKIT_HOST ??
  runtimeConfig.livekit?.host ??
  projectConfig.livekit.host;
const LIVEKIT_API_KEY =
  process.env.LIVEKIT_API_KEY ??
  runtimeConfig.livekit?.api_key ??
  projectConfig.livekit.apiKey;
const LIVEKIT_API_SECRET =
  process.env.LIVEKIT_API_SECRET ??
  runtimeConfig.livekit?.api_secret ??
  projectConfig.livekit.apiSecret;
const LIVEKIT_DEFAULT_TTL_SECONDS = Number(
  process.env.LIVEKIT_TOKEN_TTL_SECONDS ??
    runtimeConfig.livekit?.token_ttl_seconds ??
    projectConfig.livekit.tokenTtlSeconds ??
    600,
);

const VERTEX_SEARCH_PROJECT =
  process.env.VERTEX_SEARCH_PROJECT ??
  runtimeConfig.vertexsearch?.project_id ??
  projectConfig.vertexSearch?.projectId ??
  firebaseProjectId;

const VERTEX_SEARCH_LOCATION =
  process.env.VERTEX_SEARCH_LOCATION ??
  runtimeConfig.vertexsearch?.location ??
  projectConfig.vertexSearch?.location ??
  'global';

const VERTEX_SEARCH_APP_ID =
  process.env.VERTEX_SEARCH_APP_ID ??
  runtimeConfig.vertexsearch?.app_id ??
  projectConfig.vertexSearch?.appId ??
  '';

const VERTEX_SEARCH_DATA_STORE_ID =
  process.env.VERTEX_SEARCH_DATA_STORE_ID ??
  runtimeConfig.vertexsearch?.data_store_id ??
  projectConfig.vertexSearch?.dataStoreId ??
  '';

const VERTEX_SEARCH_TOP_K = Number(
  process.env.VERTEX_SEARCH_TOP_K ??
    runtimeConfig.vertexsearch?.top_k ??
    projectConfig.vertexSearch?.topK ??
    5,
);

const WORKER_JOB_PROJECT =
  process.env.WORKER_JOB_PROJECT ??
  runtimeConfig.workerjob?.project_id ??
  firebaseProjectId;

const WORKER_JOB_REGION =
  process.env.WORKER_JOB_REGION ??
  runtimeConfig.workerjob?.region ??
  firebaseFunctionsRegion;

const WORKER_JOB_NAME =
  process.env.WORKER_JOB_NAME ??
  runtimeConfig.workerjob?.job_name ??
  '';

const SEARCH_API_ENDPOINT =
  VERTEX_SEARCH_LOCATION === 'global'
    ? undefined
    : `${VERTEX_SEARCH_LOCATION}-discoveryengine.googleapis.com`;

const auth = new GoogleAuth({
  scopes: ['https://www.googleapis.com/auth/cloud-platform'],
});

const searchClient = new SearchServiceClient(
  SEARCH_API_ENDPOINT ? { apiEndpoint: SEARCH_API_ENDPOINT } : {},
);

type FirebaseAuthResult = admin.auth.DecodedIdToken;

interface LiveKitTokenRequestBody {
  roomName?: string;
  participantName?: string;
  metadata?: Record<string, unknown>;
  ttlSeconds?: number;
}

function isCorsPreflight(req: Request) {
  return req.method === 'OPTIONS';
}

async function runWorkerJob(roomName: string): Promise<void> {
  if (process.env.FUNCTIONS_EMULATOR === 'true') {
    functions.logger.info('Skipping worker job start in emulator.');
    return;
  }
  if (!WORKER_JOB_NAME || !WORKER_JOB_PROJECT || !WORKER_JOB_REGION) {
    throw new Error('Worker job not configured (missing name/project/region).');
  }
  const url = `https://run.googleapis.com/v2/projects/${WORKER_JOB_PROJECT}/locations/${WORKER_JOB_REGION}/jobs/${WORKER_JOB_NAME}:run`;
  const client = await auth.getClient();
  await client.request({
    url,
    method: 'POST',
    data: {
      overrides: {
        containerOverrides: [
          {
            env: [{ name: 'LIVEKIT_ROOM', value: roomName }],
          },
        ],
      },
    },
  });
}

function ensureEnvOrRespond(
  res: Response,
): { host: string; apiKey: string; apiSecret: string } | null {
  if (!LIVEKIT_HOST || !LIVEKIT_API_KEY || !LIVEKIT_API_SECRET) {
    functions.logger.error('Missing LiveKit environment variables', {
      hasHost: Boolean(LIVEKIT_HOST),
      hasKey: Boolean(LIVEKIT_API_KEY),
      hasSecret: Boolean(LIVEKIT_API_SECRET),
    });
    res.status(500).json({
      error: 'LiveKit configuration missing on server',
      missing: {
        host: Boolean(LIVEKIT_HOST),
        apiKey: Boolean(LIVEKIT_API_KEY),
        apiSecret: Boolean(LIVEKIT_API_SECRET),
      },
    });
    return null;
  }
  return {
    host: LIVEKIT_HOST,
    apiKey: LIVEKIT_API_KEY,
    apiSecret: LIVEKIT_API_SECRET,
  };
}

async function authenticateRequest(
  req: Request,
  res: Response,
): Promise<FirebaseAuthResult | null> {
  const appCheckToken = req.header(APP_CHECK_HEADER);
  if (!appCheckToken) {
    res.status(401).json({ error: 'Missing App Check token' });
    return null;
  }

  try {
    await admin.appCheck().verifyToken(appCheckToken);
  } catch (error) {
    functions.logger.warn('Invalid App Check token', error);
    res.status(401).json({ error: 'Invalid App Check token' });
    return null;
  }

  const authHeader = req.header(AUTHORIZATION_HEADER);
  if (!authHeader?.startsWith('Bearer ')) {
    res.status(401).json({ error: 'Missing Authorization header' });
    return null;
  }

  const idToken = authHeader.substring('Bearer '.length);
  try {
    return await admin.auth().verifyIdToken(idToken);
  } catch (error) {
    functions.logger.warn('Invalid Firebase ID token', error);
    res.status(401).json({ error: 'Invalid ID token' });
    return null;
  }
}

export const ping = functions
  .region(firebaseFunctionsRegion)
  .https.onRequest(async (req, res) => {
    corsHandler(req, res, async () => {
      if (isCorsPreflight(req)) {
        res.status(204).send('');
        return;
      }

      if (req.method !== 'POST') {
        res.status(405).json({ error: 'Method not allowed' });
        return;
      }

      const decodedIdToken = await authenticateRequest(req, res);
      if (!decodedIdToken) {
        return;
      }

      res.status(200).json({
        ok: true,
        uid: decodedIdToken.uid,
        appCheckVerified: true,
        timestamp: new Date().toISOString(),
      });
    });
  });

export const livekitToken = functions
  .region(firebaseFunctionsRegion)
  .https.onRequest(async (req, res) => {
    corsHandler(req, res, async () => {
      if (isCorsPreflight(req)) {
        res.status(204).send('');
        return;
      }

      if (req.method !== 'POST') {
        res.status(405).json({ error: 'Method not allowed' });
        return;
      }

      const decodedIdToken = await authenticateRequest(req, res);
      if (!decodedIdToken) {
        return;
      }

      const env = ensureEnvOrRespond(res);
      if (!env) {
        return;
      }

      const body = (req.body ?? {}) as LiveKitTokenRequestBody;
      const identity = decodedIdToken.uid;
      const safeIdentity = identity.replace(/[^a-zA-Z0-9_-]/g, '-');
      const roomName = `room-${safeIdentity}`;

      try {
        await runWorkerJob(roomName);
      } catch (error) {
        functions.logger.error('Failed to start worker job', error);
        res.status(500).json({ error: 'Failed to start worker job' });
        return;
      }

      const ttlSeconds =
        typeof body.ttlSeconds === 'number' && body.ttlSeconds > 0
          ? Math.min(body.ttlSeconds, 3600)
          : LIVEKIT_DEFAULT_TTL_SECONDS;

      const participantName =
        body.participantName ??
        decodedIdToken.name ??
        `guest-${identity.substring(0, 6)}`;

      const metadata = {
        displayName: participantName,
        uid: identity,
        app: firebaseProjectId,
        providedMetadata: body.metadata ?? {},
      };

      const accessToken = new AccessToken(env.apiKey, env.apiSecret, {
        identity,
        ttl: ttlSeconds,
        metadata: JSON.stringify(metadata),
        name: participantName,
      });

      accessToken.addGrant({
        roomJoin: true,
        room: roomName,
        canPublish: true,
        canSubscribe: true,
        canPublishData: true,
      });

      try {
        const jwt = await accessToken.toJwt();
        const expiresAt = new Date(Date.now() + ttlSeconds * 1000);

        functions.logger.info('Issued LiveKit token', {
          uid: identity,
          room: roomName,
          ttlSeconds,
        });

        res.status(200).json({
          token: jwt,
          serverUrl: env.host,
          identity,
          room: roomName,
          ttlSeconds,
          expiresAt: expiresAt.toISOString(),
          issuedAt: new Date().toISOString(),
          metadata,
        });
      } catch (error) {
        functions.logger.error('Failed to issue LiveKit token', error);
        res.status(500).json({ error: 'Failed to issue LiveKit token' });
      }
    });
  });

type RagSearchResponse = {
  query: string;
  results: Array<{
    id?: string | null;
    uri?: string | null;
    title?: string | null;
    snippet?: string;
    score?: number;
  }>;
};

export const ragSearch = functions
  .region(firebaseFunctionsRegion)
  .https.onRequest(async (req, res) => {
    corsHandler(req, res, async () => {
      if (isCorsPreflight(req)) {
        res.status(204).send('');
        return;
      }

      if (req.method !== 'POST') {
        res.status(405).json({ error: 'Method not allowed' });
        return;
      }

      const decodedIdToken = await authenticateRequest(req, res);
      if (!decodedIdToken) {
        return;
      }

      if (!VERTEX_SEARCH_APP_ID || !VERTEX_SEARCH_DATA_STORE_ID) {
        res.status(500).json({
          error:
            'Vertex Search not configured (missing appId or dataStoreId). Atualize config/project_config.json e functions config.',
        });
        return;
      }

      const body = (req.body ?? {}) as { query?: string; topK?: number };
      const query = (body.query ?? '').toString().trim();
      if (!query) {
        res.status(400).json({ error: 'Missing query' });
        return;
      }
      const requestedTopK = Number(body.topK);
      const pageSize =
        Number.isFinite(requestedTopK) && requestedTopK > 0
          ? Math.min(requestedTopK, 10)
          : Math.min(Math.max(VERTEX_SEARCH_TOP_K, 1), 10);

      const servingConfig = [
        'projects',
        VERTEX_SEARCH_PROJECT,
        'locations',
        VERTEX_SEARCH_LOCATION,
        'collections',
        'default_collection',
        'dataStores',
        VERTEX_SEARCH_DATA_STORE_ID,
        'servingConfigs',
        'default_serving_config',
      ].join('/');

      const request = {
        servingConfig,
        query,
        pageSize,
        queryExpansionSpec: { condition: 'AUTO' as const },
        spellCorrectionSpec: { mode: 'AUTO' as const },
      };

      const results: RagSearchResponse['results'] = [];
      try {
        for await (const result of searchClient.searchAsync(request)) {
          const document = result.document;
          const docAny = document as any;
          const resultAny = result as any;
          const derived =
            (document?.derivedStructData as Record<string, unknown> | undefined) ??
            {};
          const struct =
            (document?.structData as Record<string, unknown> | undefined) ?? {};

          const extractiveAnswers = Array.isArray(
            (derived as any)?.extractive_answers,
          )
            ? (derived as any).extractive_answers
            : Array.isArray((derived as any)?.extractive_answer)
            ? (derived as any).extractive_answer
            : [];
          const snippets: string[] = [];
          for (const answer of extractiveAnswers) {
            if (typeof answer?.content === 'string') {
              snippets.push(answer.content);
            }
          }
          const fallbackSnippet =
            typeof (derived as any)?.snippet === 'string'
              ? (derived as any).snippet
              : typeof (struct as any)?.content === 'string'
              ? (struct as any).content
              : undefined;

          results.push({
            id: document?.id ?? (document as any)?.name ?? null,
            uri: docAny?.uri ?? (struct as any)?.uri ?? null,
            title:
              docAny?.title ??
              (struct as any)?.title ??
              (struct as any)?.file_name ??
              null,
            snippet: snippets.join(' ').trim() || fallbackSnippet,
            score: typeof resultAny?.modelScore === 'number'
              ? resultAny.modelScore
              : undefined,
          });
        }
      } catch (error) {
        functions.logger.error('Vertex Search query failed', error);
        res.status(500).json({ error: 'Vertex Search query failed' });
        return;
      }

      const response: RagSearchResponse = {
        query,
        results,
      };
      res.status(200).json(response);
    });
  });
