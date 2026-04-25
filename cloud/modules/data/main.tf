locals {
  prefix      = var.prefix
  name_prefix = "${local.prefix}${var.environment}-"
  tags        = merge(var.common_tags, { Service = "data" })
}

resource "aws_secretsmanager_secret" "discord_webhook" {
  name                    = "${local.name_prefix}${var.discord_webhook_secret_name}"
  recovery_window_in_days = 0
  tags                    = local.tags
}

resource "aws_secretsmanager_secret_version" "discord_webhook" {
  count = var.discord_webhook_url != "" ? 1 : 0

  secret_id     = aws_secretsmanager_secret.discord_webhook.id
  secret_string = jsonencode({ url = var.discord_webhook_url })
}

resource "aws_secretsmanager_secret" "webhook_auth" {
  name                    = "${local.name_prefix}${var.webhook_auth_secret_name}"
  recovery_window_in_days = 0
  tags                    = local.tags
}

resource "aws_secretsmanager_secret_version" "webhook_auth" {
  count = var.webhook_auth_token != "" ? 1 : 0

  secret_id     = aws_secretsmanager_secret.webhook_auth.id
  secret_string = jsonencode({ token = var.webhook_auth_token })
}
