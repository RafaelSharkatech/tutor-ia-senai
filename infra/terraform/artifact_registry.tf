resource "google_artifact_registry_repository" "worker" {
  location      = var.artifact_region
  repository_id = local.artifact_repository_id
  description   = "Imagens do worker do projeto ${var.name_prefix}"
  format        = "DOCKER"
  labels        = local.labels

  depends_on = [
    google_project_service.enabled["artifactregistry.googleapis.com"],
  ]
}
