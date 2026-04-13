resource "null_resource" "build_worker_image" {
  count = var.build_worker_image ? 1 : 0

  triggers = {
    worker_image_uri = local.worker_image_uri
    source_hash      = local.worker_source_hash
  }

  provisioner "local-exec" {
    command     = "cd \"${local.repo_root}\" && gcloud builds submit . --project=\"${var.project_id}\" --config=\"cloudbuild.yaml\" --substitutions=_WORKER_IMAGE_URI=${local.worker_image_uri}"
    interpreter = ["/bin/bash", "-lc"]
  }

  depends_on = [
    google_artifact_registry_repository.worker,
    google_project_iam_member.cloudbuild_artifact_writer,
    google_project_service.enabled["cloudbuild.googleapis.com"],
  ]
}

resource "google_cloud_run_v2_job" "worker" {
  provider             = google-beta
  name                 = local.worker_job_name
  location             = var.region
  deletion_protection  = false
  launch_stage         = "GA"
  labels               = local.labels

  template {
    template {
      service_account = google_service_account.worker_runtime.email
      timeout         = "${var.worker_timeout_seconds}s"
      max_retries     = var.worker_max_retries

      containers {
        image = local.worker_image_uri

        resources {
          limits = {
            cpu    = var.worker_cpu
            memory = var.worker_memory
          }
        }

        env {
          name  = "GOOGLE_CLOUD_PROJECT"
          value = var.project_id
        }

        env {
          name  = "LIVEKIT_HOST"
          value = var.livekit_host
        }

        env {
          name  = "LIVEKIT_ROOM"
          value = "room-placeholder"
        }

        env {
          name  = "WORKER_IDENTITY"
          value = var.worker_identity
        }

        env {
          name  = "STT_LANGUAGE"
          value = var.stt_language
        }

        env {
          name  = "TTS_LANGUAGE"
          value = var.tts_language
        }

        env {
          name  = "TTS_VOICE"
          value = var.tts_voice
        }

        env {
          name  = "TTS_SAMPLE_RATE"
          value = tostring(var.tts_sample_rate)
        }

        env {
          name  = "RESPONSE_TRACK_NAME"
          value = var.response_track_name
        }

        env {
          name  = "GEMINI_MODEL"
          value = var.gemini_model
        }

        env {
          name  = "GEMINI_LOCATION"
          value = var.gemini_location
        }

        env {
          name  = "GEMINI_SYSTEM_PROMPT"
          value = var.gemini_system_prompt
        }

        env {
          name  = "VERTEX_SEARCH_PROJECT"
          value = local.vertex_search_project_id
        }

        env {
          name  = "VERTEX_SEARCH_LOCATION"
          value = var.vertex_search_location
        }

        env {
          name  = "VERTEX_SEARCH_APP_ID"
          value = var.vertex_search_app_id
        }

        env {
          name  = "VERTEX_SEARCH_DATA_STORE_ID"
          value = var.vertex_search_data_store_id
        }

        env {
          name  = "VERTEX_SEARCH_TOP_K"
          value = tostring(var.vertex_search_top_k)
        }

        env {
          name  = "WORKER_IDLE_TIMEOUT_MS"
          value = tostring(var.worker_idle_timeout_ms)
        }

        env {
          name  = "VAD_SPEECH_THRESHOLD"
          value = tostring(var.vad_speech_threshold)
        }

        env {
          name  = "VAD_SILENCE_MS"
          value = tostring(var.vad_silence_ms)
        }

        env {
          name  = "VAD_MIN_SPEECH_MS"
          value = tostring(var.vad_min_speech_ms)
        }

        env {
          name  = "VAD_MAX_SEGMENT_MS"
          value = tostring(var.vad_max_segment_ms)
        }

        env {
          name = "LIVEKIT_API_KEY"
          value_source {
            secret_key_ref {
              secret  = google_secret_manager_secret.livekit_api_key.secret_id
              version = "latest"
            }
          }
        }

        env {
          name = "LIVEKIT_API_SECRET"
          value_source {
            secret_key_ref {
              secret  = google_secret_manager_secret.livekit_api_secret.secret_id
              version = "latest"
            }
          }
        }
      }
    }
  }

  depends_on = [
    google_project_service.enabled["run.googleapis.com"],
    google_secret_manager_secret_version.livekit_api_key,
    google_secret_manager_secret_version.livekit_api_secret,
    null_resource.build_worker_image,
  ]
}
