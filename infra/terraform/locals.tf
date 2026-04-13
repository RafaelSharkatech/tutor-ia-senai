data "google_project" "current" {
  project_id = var.project_id
}

locals {
  repo_root = abspath("${path.module}/../..")

  default_labels = {
    application = var.name_prefix
    managed_by  = "terraform"
    repository  = "tutor-ia-senai"
  }

  labels = merge(local.default_labels, var.labels)

  artifact_repository_id  = var.artifact_repository_id != "" ? var.artifact_repository_id : "${var.name_prefix}-artifacts"
  functions_source_bucket = var.functions_source_bucket_name != "" ? var.functions_source_bucket_name : "${var.project_id}-${var.name_prefix}-functions-src"
  rag_bucket              = var.rag_bucket_name != "" ? var.rag_bucket_name : "${var.project_id}-${var.name_prefix}-rag"
  worker_job_name         = var.worker_job_name != "" ? var.worker_job_name : "${var.name_prefix}-worker"
  worker_image_uri        = var.worker_image_uri != "" ? var.worker_image_uri : "${var.artifact_region}-docker.pkg.dev/${var.project_id}/${local.artifact_repository_id}/worker:${var.worker_image_tag}"

  vertex_search_project_id = coalesce(var.vertex_search_project_id, var.project_id)

  enabled_services = toset([
    "aiplatform.googleapis.com",
    "artifactregistry.googleapis.com",
    "cloudbuild.googleapis.com",
    "cloudfunctions.googleapis.com",
    "discoveryengine.googleapis.com",
    "firebase.googleapis.com",
    "firebaseappcheck.googleapis.com",
    "firestore.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "identitytoolkit.googleapis.com",
    "run.googleapis.com",
    "secretmanager.googleapis.com",
    "serviceusage.googleapis.com",
    "speech.googleapis.com",
    "storage.googleapis.com",
    "texttospeech.googleapis.com",
  ])

  function_definitions = {
    ping = {
      name        = "${var.name_prefix}-ping"
      entry_point = "ping"
    }
    livekit_token = {
      name        = "${var.name_prefix}-livekit-token"
      entry_point = "livekitToken"
    }
    rag_search = {
      name        = "${var.name_prefix}-rag-search"
      entry_point = "ragSearch"
    }
  }

  functions_source_hash = sha256(join("", concat(
    [
      filesha256("${local.repo_root}/functions/package.json"),
      filesha256("${local.repo_root}/functions/package-lock.json"),
      filesha256("${local.repo_root}/functions/tsconfig.json"),
      filesha256("${local.repo_root}/functions/src/index.ts"),
      filesha256("${local.repo_root}/functions/src/config/project_config.json"),
    ],
    [for file in fileset("${local.repo_root}/functions/src", "**") : filesha256("${local.repo_root}/functions/src/${file}")]
  )))

  worker_source_hash = sha256(join("", concat(
    [
      filesha256("${local.repo_root}/worker/Dockerfile"),
      filesha256("${local.repo_root}/worker/package.json"),
      filesha256("${local.repo_root}/worker/package-lock.json"),
      filesha256("${local.repo_root}/worker/tsconfig.json"),
      filesha256("${local.repo_root}/cloudbuild.yaml"),
      filesha256("${local.repo_root}/config/project_config.json"),
    ],
    [for file in fileset("${local.repo_root}/worker/src", "**") : filesha256("${local.repo_root}/worker/src/${file}")]
  )))
}
