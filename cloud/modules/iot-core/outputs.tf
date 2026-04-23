output "iot_data_endpoint" {
  description = "AWS IoT Data-ATS endpoint"
  value       = data.aws_iot_endpoint.data_ats.endpoint_address
}

output "shelly_thing_name" {
  description = "Shelly thing name"
  value       = aws_iot_thing.shelly.name
}

output "esp_thing_name" {
  description = "ESP32 thing name"
  value       = aws_iot_thing.esp.name
}

output "shelly_certificate_pem" {
  description = "Shelly device certificate PEM"
  value       = aws_iot_certificate.shelly.certificate_pem
  sensitive   = true
}

output "shelly_private_key" {
  description = "Shelly private key PEM"
  value       = aws_iot_certificate.shelly.private_key
  sensitive   = true
}

output "esp_certificate_pem" {
  description = "ESP32 device certificate PEM"
  value       = aws_iot_certificate.esp.certificate_pem
  sensitive   = true
}

output "esp_private_key" {
  description = "ESP32 private key PEM"
  value       = aws_iot_certificate.esp.private_key
  sensitive   = true
}

output "control_topic" {
  description = "Control MQTT topic"
  value       = var.control_topic
}

output "telemetry_topic_filter" {
  description = "Telemetry MQTT filter"
  value       = var.telemetry_topic_filter
}

output "shelly_publish_topic" {
  description = "Exact telemetry topic expected from Shelly"
  value       = local.shelly_topic
}
