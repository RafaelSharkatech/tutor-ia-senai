data "archive_file" "functions_source" {
  type        = "zip"
  source_dir  = "${local.repo_root}/functions"
  output_path = "${path.module}/functions-source.zip"
  excludes    = [
    "node_modules",
    ".runtimeconfig.json",
  ]
}

resource "google_storage_bucket_object" "functions_source" {
  name   = "functions/functions-${data.archive_file.functions_source.output_md5}.zip"
  bucket = google_storage_bucket.functions_source.name
  source = data.archive_file.functions_source.output_path
}

resource "google_cloudfunctions2_function" "http" {
  provider = google-beta
  for_each = local.function_definitions

  name     = each.value.name
  location = var.region
  labels   = local.labels

  build_config {
    runtime     = var.functions_runtime
    entry_point = each.value.entry_point

    source {
      storage_source {
        bucket = google_storage_bucket.functions_source.name
        object = google_storage_bucket_object.functions_source.name
      }
    }
  }

  service_config {
    max_instance_count               = var.functions_max_instance_count
    timeout_seconds                  = var.functions_timeout_seconds
    available_memory                 = var.functions_available_memory
    ingress_settings                 = "ALLOW_ALL"
    all_traffic_on_latest_revision   = true
    service_account_email            = google_service_account.functions_runtime.email

    environment_variables = {
      LIVEKIT_HOST               = var.livekit_host
      LIVEKIT_TOKEN_TTL_SECONDS  = tostring(var.livekit_token_ttl_seconds)
      VERTEX_SEARCH_PROJECT      = local.vertex_search_project_id
      VERTEX_SEARCH_LOCATION     = var.vertex_search_location
      VERTEX_SEARCH_APP_ID       = var.vertex_search_app_id
      VERTEX_SEARCH_DATA_STORE_ID = var.vertex_search_data_store_id
      VERTEX_SEARCH_TOP_K        = tostring(var.vertex_search_top_k)
      WORKER_JOB_PROJECT         = var.project_id
      WORKER_JOB_REGION          = var.region
      WORKER_JOB_NAME            = google_cloud_run_v2_job.worker.name
    }

    secret_environment_variables {
      key        = "LIVEKIT_API_KEY"
      project_id = var.project_id
      secret     = google_secret_manager_secret.livekit_api_key.secret_id
      version    = "latest"
    }

    secret_environment_variables {
      key        = "LIVEKIT_API_SECRET"
      project_id = var.project_id
      secret     = google_secret_manager_secret.livekit_api_secret.secret_id
      version    = "latest"
    }
  }

  depends_on = [
    google_cloud_run_v2_job.worker,
    google_project_service.enabled["cloudfunctions.googleapis.com"],
    google_secret_manager_secret_version.livekit_api_key,
    google_secret_manager_secret_version.livekit_api_secret,
  ]
}
