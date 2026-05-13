output "api_endpoint" {
  description = "Base HTTP API endpoint"
  value       = module.http_api.api_endpoint
}

output "silence_endpoint" {
  description = "Silence route URL"
  value       = "${module.http_api.api_endpoint}/v1/buzzer/silence"
}
