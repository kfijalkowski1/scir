locals {
  prefix      = var.prefix
  name_prefix = "${local.prefix}${var.environment}-"
  tags        = merge(var.common_tags, { Service = "data" })

  timestream_database_name = replace("${local.name_prefix}washer", "-", "_")
  readings_table_name      = replace("${local.name_prefix}${var.readings_table_name}", "-", "_")
  events_table_name        = replace("${local.name_prefix}${var.events_table_name}", "-", "_")
}

resource "aws_timestreamwrite_database" "this" {
  database_name = local.timestream_database_name
  tags          = local.tags
}

resource "aws_timestreamwrite_table" "readings" {
  database_name = aws_timestreamwrite_database.this.database_name
  table_name    = local.readings_table_name

  retention_properties {
    memory_store_retention_period_in_hours  = var.memory_retention_hours
    magnetic_store_retention_period_in_days = var.magnetic_retention_days
  }

  tags = local.tags
}

resource "aws_timestreamwrite_table" "events" {
  database_name = aws_timestreamwrite_database.this.database_name
  table_name    = local.events_table_name

  retention_properties {
    memory_store_retention_period_in_hours  = var.memory_retention_hours
    magnetic_store_retention_period_in_days = var.magnetic_retention_days
  }

  tags = local.tags
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
