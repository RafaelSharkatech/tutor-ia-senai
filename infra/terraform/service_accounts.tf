resource "google_service_account" "functions_runtime" {
  account_id   = substr(replace("${var.name_prefix}-functions", "_", "-"), 0, 30)
  display_name = "Runtime SA for ${var.name_prefix} functions"
}

resource "google_service_account" "worker_runtime" {
  account_id   = substr(replace("${var.name_prefix}-worker", "_", "-"), 0, 30)
  display_name = "Runtime SA for ${var.name_prefix} worker"
}

resource "google_project_iam_member" "functions_run_developer" {
  project = var.project_id
  role    = "roles/run.developer"
  member  = "serviceAccount:${google_service_account.functions_runtime.email}"
}

resource "google_service_account_iam_member" "functions_can_use_worker_sa" {
  service_account_id = google_service_account.worker_runtime.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.functions_runtime.email}"
}

resource "google_project_iam_member" "functions_secret_accessor" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.functions_runtime.email}"
}

resource "google_project_iam_member" "worker_secret_accessor" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.worker_runtime.email}"
}

resource "google_project_iam_member" "worker_logging" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.worker_runtime.email}"
}

resource "google_project_iam_member" "worker_aiplatform" {
  project = var.project_id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${google_service_account.worker_runtime.email}"
}

resource "google_project_iam_member" "worker_discoveryengine" {
  project = var.project_id
  role    = "roles/discoveryengine.user"
  member  = "serviceAccount:${google_service_account.worker_runtime.email}"
}

resource "google_project_iam_member" "worker_speech" {
  project = var.project_id
  role    = "roles/speech.client"
  member  = "serviceAccount:${google_service_account.worker_runtime.email}"
}

resource "google_project_iam_member" "worker_tts" {
  project = var.project_id
  role    = "roles/texttospeech.user"
  member  = "serviceAccount:${google_service_account.worker_runtime.email}"
}

resource "google_project_iam_member" "worker_storage_viewer" {
  project = var.project_id
  role    = "roles/storage.objectViewer"
  member  = "serviceAccount:${google_service_account.worker_runtime.email}"
}

resource "google_project_iam_member" "cloudbuild_artifact_writer" {
  project = var.project_id
  role    = "roles/artifactregistry.writer"
  member  = "serviceAccount:${data.google_project.current.number}@cloudbuild.gserviceaccount.com"
}
