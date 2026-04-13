output "firebase_web_app_id" {
  value = google_firebase_web_app.web.app_id
}

output "firebase_web_config" {
  value = {
    apiKey            = data.google_firebase_web_app_config.web.api_key
    appId             = google_firebase_web_app.web.app_id
    authDomain        = data.google_firebase_web_app_config.web.auth_domain
    messagingSenderId = data.google_firebase_web_app_config.web.messaging_sender_id
    projectId         = var.project_id
    storageBucket     = data.google_firebase_web_app_config.web.storage_bucket
    measurementId     = try(data.google_firebase_web_app_config.web.measurement_id, null)
  }
}

output "firebase_options_snippet" {
  value = <<-EOT
  static const FirebaseOptions web = FirebaseOptions(
    apiKey: '${data.google_firebase_web_app_config.web.api_key}',
    appId: '${google_firebase_web_app.web.app_id}',
    messagingSenderId: '${data.google_firebase_web_app_config.web.messaging_sender_id}',
    projectId: '${var.project_id}',
    authDomain: '${data.google_firebase_web_app_config.web.auth_domain}',
    storageBucket: '${data.google_firebase_web_app_config.web.storage_bucket}',
    measurementId: '${try(data.google_firebase_web_app_config.web.measurement_id, "")}',
  );
  EOT
}

output "app_config_snippet" {
  value = <<-EOT
  static const String firebaseProjectId = '${var.project_id}';
  static const String firebaseFunctionsRegion = '${var.region}';
  static const String reCaptchaV3SiteKey = '${var.re_captcha_v3_site_key}';
  static const String livekitTokenFunctionName = 'livekitToken';
  static const String assistantIdentity = '${var.worker_identity}';
  EOT
}

output "functions_urls" {
  value = {
    for key, fn in google_cloudfunctions2_function.http :
    key => fn.service_config[0].uri
  }
}

output "worker_job_name" {
  value = google_cloud_run_v2_job.worker.name
}

output "worker_image_uri" {
  value = local.worker_image_uri
}

output "rag_bucket_name" {
  value = google_storage_bucket.rag.name
}

output "artifact_registry_repository" {
  value = google_artifact_registry_repository.worker.id
}
