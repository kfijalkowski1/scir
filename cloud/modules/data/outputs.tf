output "timestream_database_name" {
  description = "Timestream database name"
  value       = aws_timestreamwrite_database.this.database_name
}

output "readings_table_name" {
  description = "Timestream readings table name"
  value       = aws_timestreamwrite_table.readings.table_name
}

output "events_table_name" {
  description = "Timestream events table name"
  value       = aws_timestreamwrite_table.events.table_name
}

output "timestream_database_arn" {
  description = "Timestream database ARN"
  value       = aws_timestreamwrite_database.this.arn
}

output "discord_webhook_secret_arn" {
  description = "Discord webhook secret ARN"
  value       = aws_secretsmanager_secret.discord_webhook.arn
}

output "webhook_auth_secret_arn" {
  description = "Webhook auth token secret ARN"
  value       = aws_secretsmanager_secret.webhook_auth.arn
}
