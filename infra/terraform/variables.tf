variable "project_id" {
  description = "ID do projeto Google Cloud/Firebase já existente."
  type        = string
}

variable "region" {
  description = "Região principal para Cloud Functions e Cloud Run Job."
  type        = string
  default     = "us-central1"
}

variable "artifact_region" {
  description = "Região do Artifact Registry."
  type        = string
  default     = "us-central1"
}

variable "bucket_location" {
  description = "Localização dos buckets GCS."
  type        = string
  default     = "US-CENTRAL1"
}

variable "firestore_location" {
  description = "Localização do banco Firestore."
  type        = string
  default     = "us-central1"
}

variable "name_prefix" {
  description = "Prefixo nominal dos recursos."
  type        = string
  default     = "tutor-ia-senai"
}

variable "firebase_web_app_display_name" {
  description = "Nome do app Web no Firebase."
  type        = string
  default     = "Tutor IA SENAI Web"
}

variable "re_captcha_v3_site_key" {
  description = "Site key pública do reCAPTCHA v3 usada pelo App Check."
  type        = string
}

variable "livekit_host" {
  description = "Host WSS do projeto LiveKit."
  type        = string
}

variable "livekit_api_key" {
  description = "API key do LiveKit."
  type        = string
  sensitive   = true
}

variable "livekit_api_secret" {
  description = "API secret do LiveKit."
  type        = string
  sensitive   = true
}

variable "livekit_token_ttl_seconds" {
  description = "TTL padrão do token LiveKit emitido pela Function."
  type        = number
  default     = 600
}

variable "vertex_search_project_id" {
  description = "Projeto que hospeda o Vertex AI Search/Discovery Engine."
  type        = string
  default     = null
  nullable    = true
}

variable "vertex_search_location" {
  description = "Localização do Discovery Engine."
  type        = string
  default     = "global"
}

variable "vertex_search_app_id" {
  description = "ID do app do Vertex AI Search já existente."
  type        = string
}

variable "vertex_search_data_store_id" {
  description = "ID do data store do Vertex AI Search já existente."
  type        = string
}

variable "vertex_search_top_k" {
  description = "Top-K padrão das consultas RAG."
  type        = number
  default     = 5
}

variable "gemini_model" {
  description = "Modelo Gemini usado pelo worker."
  type        = string
  default     = "gemini-2.5-flash"
}

variable "gemini_location" {
  description = "Localização do Vertex AI/Gemini."
  type        = string
  default     = "us-central1"
}

variable "gemini_system_prompt" {
  description = "Prompt de sistema da IA."
  type        = string
}

variable "stt_language" {
  description = "Idioma do Speech-to-Text."
  type        = string
  default     = "pt-BR"
}

variable "tts_language" {
  description = "Idioma do Text-to-Speech."
  type        = string
  default     = "pt-BR"
}

variable "tts_voice" {
  description = "Voz do Text-to-Speech."
  type        = string
  default     = "pt-BR-Neural2-B"
}

variable "tts_sample_rate" {
  description = "Sample rate do TTS."
  type        = number
  default     = 24000
}

variable "response_track_name" {
  description = "Nome da trilha de áudio publicada pelo worker."
  type        = string
  default     = "assistant"
}

variable "worker_identity" {
  description = "Identity usada pelo worker no LiveKit."
  type        = string
  default     = "assistant-bot"
}

variable "worker_idle_timeout_ms" {
  description = "Tempo máximo sem participantes antes do shutdown do worker."
  type        = number
  default     = 90000
}

variable "vad_speech_threshold" {
  description = "Threshold do VAD."
  type        = number
  default     = 1100
}

variable "vad_silence_ms" {
  description = "Silêncio para fechamento do segmento."
  type        = number
  default     = 1000
}

variable "vad_min_speech_ms" {
  description = "Duração mínima de fala."
  type        = number
  default     = 1000
}

variable "vad_max_segment_ms" {
  description = "Duração máxima de um segmento de voz."
  type        = number
  default     = 15000
}

variable "functions_runtime" {
  description = "Runtime Node.js para Cloud Functions 2nd gen."
  type        = string
  default     = "nodejs22"
}

variable "functions_available_memory" {
  description = "Memória por Function."
  type        = string
  default     = "256M"
}

variable "functions_timeout_seconds" {
  description = "Timeout das Functions."
  type        = number
  default     = 60
}

variable "functions_max_instance_count" {
  description = "Máximo de instâncias por Function."
  type        = number
  default     = 3
}

variable "worker_memory" {
  description = "Memória do Cloud Run Job."
  type        = string
  default     = "1Gi"
}

variable "worker_cpu" {
  description = "CPU do Cloud Run Job."
  type        = string
  default     = "1"
}

variable "worker_timeout_seconds" {
  description = "Timeout do Cloud Run Job."
  type        = number
  default     = 3600
}

variable "worker_max_retries" {
  description = "Máximo de retries do Cloud Run Job."
  type        = number
  default     = 0
}

variable "artifact_repository_id" {
  description = "ID do repositório no Artifact Registry. Se vazio, é derivado do prefixo."
  type        = string
  default     = ""
}

variable "functions_source_bucket_name" {
  description = "Nome do bucket de source archive das Functions. Se vazio, é derivado."
  type        = string
  default     = ""
}

variable "rag_bucket_name" {
  description = "Nome do bucket de documentos RAG. Se vazio, é derivado."
  type        = string
  default     = ""
}

variable "worker_job_name" {
  description = "Nome do Cloud Run Job. Se vazio, é derivado."
  type        = string
  default     = ""
}

variable "worker_image_uri" {
  description = "URI completa da imagem do worker. Se vazio, é derivada do Artifact Registry."
  type        = string
  default     = ""
}

variable "worker_image_tag" {
  description = "Tag padrão da imagem do worker."
  type        = string
  default     = "latest"
}

variable "build_worker_image" {
  description = "Se true, roda gcloud builds submit durante o apply para construir e publicar a imagem do worker."
  type        = bool
  default     = true
}

variable "force_destroy_buckets" {
  description = "Se true, permite destruir buckets com conteúdo."
  type        = bool
  default     = false
}

variable "labels" {
  description = "Labels adicionais para os recursos."
  type        = map(string)
  default     = {}
}
