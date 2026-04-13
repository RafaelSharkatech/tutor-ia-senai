# Terraform da solução

Este diretório provisiona a infraestrutura principal do MVP atual:

- Firebase project attachment
- Firestore
- app Web do Firebase
- bucket de documentos RAG
- bucket de source archive das Functions
- Secret Manager para segredos do LiveKit
- Artifact Registry para a imagem do worker
- Cloud Run Job do worker
- Cloud Functions HTTP (`ping`, `livekitToken`, `ragSearch`)
- IAM mínimo para execução entre Functions, worker, Discovery Engine e Cloud Build

## Pré-requisitos externos

Ainda existem dependências que não nascem dentro deste Terraform:

- projeto Google Cloud já criado
- credenciais do LiveKit já emitidas
- site key do reCAPTCHA v3 já criada
- configuração do App Check no console do Firebase
- app e data store do Vertex AI Search já criados
- `gcloud` autenticado no projeto
- `terraform` instalado na máquina que vai aplicar

## Fluxo recomendado

1. Copie `terraform.tfvars.example` para `terraform.tfvars`.
2. Preencha os valores reais.
3. Autentique o `gcloud` no projeto alvo.
4. Rode:

```bash
cd infra/terraform
terraform init
terraform plan
terraform apply
```

## Observações operacionais

- O `apply` usa `gcloud builds submit` para construir e publicar a imagem do worker quando `build_worker_image = true`.
- As Functions são implantadas como Cloud Functions 2nd gen a partir do código local em `functions/`.
- O pacote das Functions depende do script `gcp-build`, já configurado em `functions/package.json`.

## Saídas importantes

Após o `apply`, use os outputs para preencher:

- `lib/firebase_options.dart`
- `lib/config/app_config.dart`
- `config/project_config.json`
- `functions/src/config/project_config.json`

Os outputs `firebase_options_snippet` e `app_config_snippet` já devolvem trechos prontos para isso.

## Limitação conhecida

Este pacote assume que o ambiente de execução possui `bash`, `gcloud` e `terraform`. Neste workspace do Codex eu não consegui validar com `terraform validate`, porque o binário do Terraform não está instalado.
