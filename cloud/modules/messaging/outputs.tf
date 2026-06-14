output "telemetry_queue_arn" {
  description = "Telemetry queue ARN"
  value       = module.telemetry_queue.queue_arn
}

output "telemetry_queue_url" {
  description = "Telemetry queue URL"
  value       = module.telemetry_queue.queue_url
}

output "telemetry_queue_name" {
  description = "Telemetry queue name"
  value       = module.telemetry_queue.queue_name
}

output "telemetry_dlq_arn" {
  description = "Telemetry dead-letter queue ARN"
  value       = module.telemetry_queue.dead_letter_queue_arn
}

output "telemetry_topic_filter" {
  description = "MQTT topic filter for Shelly telemetry ingestion"
  value       = local.resolved_telemetry_topic_filter
}

output "control_topic" {
  description = "MQTT topic for buzzer and user interaction events"
  value       = local.resolved_control_topic
}
