resource "google_secret_manager_secret" "livekit_api_key" {
  secret_id = "${var.name_prefix}-livekit-api-key"

  replication {
    auto {}
  }

  depends_on = [
    google_project_service.enabled["secretmanager.googleapis.com"],
  ]
}

resource "google_secret_manager_secret_version" "livekit_api_key" {
  secret      = google_secret_manager_secret.livekit_api_key.id
  secret_data = var.livekit_api_key
}

resource "google_secret_manager_secret" "livekit_api_secret" {
  secret_id = "${var.name_prefix}-livekit-api-secret"

  replication {
    auto {}
  }

  depends_on = [
    google_project_service.enabled["secretmanager.googleapis.com"],
  ]
}

resource "google_secret_manager_secret_version" "livekit_api_secret" {
  secret      = google_secret_manager_secret.livekit_api_secret.id
  secret_data = var.livekit_api_secret
}
