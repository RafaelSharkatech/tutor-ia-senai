resource "google_storage_bucket" "functions_source" {
  name                        = local.functions_source_bucket
  location                    = var.bucket_location
  force_destroy               = var.force_destroy_buckets
  uniform_bucket_level_access = true
  labels                      = local.labels

  depends_on = [
    google_project_service.enabled["storage.googleapis.com"],
  ]
}

resource "google_storage_bucket" "rag" {
  name                        = local.rag_bucket
  location                    = var.bucket_location
  force_destroy               = var.force_destroy_buckets
  uniform_bucket_level_access = true
  labels                      = local.labels

  versioning {
    enabled = true
  }

  depends_on = [
    google_project_service.enabled["storage.googleapis.com"],
  ]
}

resource "google_project_service_identity" "discovery_engine" {
  provider = google-beta
  project  = var.project_id
  service  = "discoveryengine.googleapis.com"

  depends_on = [
    google_project_service.enabled["discoveryengine.googleapis.com"],
  ]
}

resource "google_storage_bucket_iam_member" "rag_discovery_engine_access" {
  bucket = google_storage_bucket.rag.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_project_service_identity.discovery_engine.email}"
}
