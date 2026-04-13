FROM node:20-slim

WORKDIR /app

# Instalamos certificados para evitar erros de TLS em hosts WSS
RUN apt-get update && apt-get install -y ca-certificates && rm -rf /var/lib/apt/lists/*

# Instala dependências (inclui dev para manter pino-pretty usado no runtime)
COPY worker/package*.json ./
RUN npm ci

# Código-fonte e config base
COPY worker/tsconfig.json ./tsconfig.json
COPY worker/src ./src
RUN mkdir -p config
COPY config/project_config.json ./config/project_config.json

# Compila TypeScript
RUN npm run build

ENV NODE_ENV=production

CMD ["node", "dist/index.js"]
