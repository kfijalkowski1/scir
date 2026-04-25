output "discord_webhook_secret_arn" {
  description = "Discord webhook secret ARN"
  value       = aws_secretsmanager_secret.discord_webhook.arn
}

output "webhook_auth_secret_arn" {
  description = "Webhook auth token secret ARN"
  value       = aws_secretsmanager_secret.webhook_auth.arn
}
