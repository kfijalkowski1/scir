data "aws_caller_identity" "current" {}

locals {
  prefix      = var.prefix
  name_prefix = "${local.prefix}${var.environment}-"
  tags        = merge(var.common_tags, { Service = "lambda-processor" })

  control_topic_arn = "arn:aws:iot:${var.aws_region}:${data.aws_caller_identity.current.account_id}:topic/${var.control_topic}"
}

module "lambda" {
  source  = "terraform-aws-modules/lambda/aws"
  version = "~> 8.8"

  function_name = "${local.name_prefix}processor"
  description   = "SCIR telemetry processor and cycle detector"
  handler       = "handler.lambda_handler"
  runtime       = "python3.12"

  source_path = "${path.module}/src"

  timeout     = 60
  memory_size = 256

  cloudwatch_logs_retention_in_days = 30

  environment_variables = {
    CONTROL_TOPIC              = var.control_topic
    IOT_DATA_ENDPOINT          = var.iot_data_endpoint
    TIMESTREAM_DATABASE        = var.timestream_database_name
    READINGS_TABLE             = var.timestream_readings_table_name
    EVENTS_TABLE               = var.timestream_events_table_name
    DISCORD_WEBHOOK_SECRET_ARN = var.discord_webhook_secret_arn
    DEVICE_ID                  = var.device_id
    START_POWER_THRESHOLD      = tostring(var.start_power_threshold)
    END_POWER_THRESHOLD        = tostring(var.end_power_threshold)
    LOW_POWER_WINDOW_SECONDS   = tostring(var.low_power_window_seconds)
  }

  attach_policy_statements = true
  policy_statements = {
    sqs_consume = {
      effect = "Allow"
      actions = [
        "sqs:ReceiveMessage",
        "sqs:DeleteMessage",
        "sqs:GetQueueAttributes",
        "sqs:ChangeMessageVisibility"
      ]
      resources = [var.telemetry_queue_arn]
    }

    timestream_write = {
      effect = "Allow"
      actions = [
        "timestream:WriteRecords",
        "timestream:DescribeEndpoints"
      ]
      resources = ["*"]
    }

    timestream_query = {
      effect = "Allow"
      actions = [
        "timestream:Select",
        "timestream:DescribeEndpoints"
      ]
      resources = ["*"]
    }

    iot_publish = {
      effect    = "Allow"
      actions   = ["iot:Publish"]
      resources = [local.control_topic_arn]
    }

    secrets_read = {
      effect    = "Allow"
      actions   = ["secretsmanager:GetSecretValue"]
      resources = [var.discord_webhook_secret_arn]
    }
  }

  event_source_mapping = {
    telemetry_batch = {
      event_source_arn                   = var.telemetry_queue_arn
      batch_size                         = var.batch_size
      maximum_batching_window_in_seconds = var.max_batching_window_seconds
      enabled                            = true
    }
  }

  tags = local.tags
}
