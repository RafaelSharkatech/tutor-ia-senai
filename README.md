# SENAI 2026 Alpha 01

Aplicação Flutter Web de demonstração para a solução de IA tutora integrada ao backend em tempo real com Firebase, Cloud Functions, LiveKit, Cloud Run e Vertex AI.

## Escopo desta cópia

Esta cópia foi mantida com foco no fluxo oficialmente compartilhável do cliente Web:

- autenticação com Firebase;
- validação com App Check;
- obtenção de token LiveKit;
- conversa por voz;
- troca de contexto textual via `chat_context`;
- envio de eventos de cena em texto via `scene_event`;
- persistência de histórico em Firestore.

## Estrutura principal

Esta cópia foi reduzida para entrega Web. Arquivos de Android, iOS, macOS, Linux e Windows não fazem parte deste material compartilhável.

- `lib/`: cliente Flutter para autenticação, sessão, chat e UI de demonstração.
- `web/`: assets e bootstrap da aplicação Web.
- `functions/`: Cloud Functions HTTP para `ping`, `livekitToken` e `ragSearch`.
- `worker/`: worker que entra na sala LiveKit e executa a pipeline de voz.
- `config/`: configuração local do projeto.
- `docs/architecture.md`: desenho da arquitetura da solução.
- `infra/terraform/`: pacote de IaC para provisionamento da infraestrutura principal.

## Configuração

Antes de executar ou publicar, substitua todos os valores sensíveis por variáveis de ambiente, secrets manager ou arquivos locais que não sejam versionados.

Pontos que exigem configuração:

- Firebase
- App Check
- LiveKit
- Cloud Run Job do worker
- Vertex AI / Vertex AI Search
- credenciais de serviço do Google Cloud

Arquivos que foram deixados propositalmente com placeholders:

- `lib/config/app_config.dart`
- `lib/firebase_options.dart`
- `config/project_config.json`
- `functions/src/config/project_config.json`
- `cloudbuild.yaml`
- `firebase.json`

## Observação

Este repositório não deve ser publicado com segredos reais, credenciais ativas, chaves de API, tokens, ou arquivos de build gerados.
