data "aws_caller_identity" "current" {}

locals {
  prefix      = var.prefix
  name_prefix = "${local.prefix}${var.environment}-"
  tags        = merge(var.common_tags, { Service = "lambda-webhook" })

  control_topic_arn = "arn:aws:iot:${var.aws_region}:${data.aws_caller_identity.current.account_id}:topic/${var.control_topic}"
}

module "lambda" {
  source  = "terraform-aws-modules/lambda/aws"
  version = "~> 8.8"

  function_name = "${local.name_prefix}webhook"
  description   = "SCIR silence webhook"
  handler       = "handler.lambda_handler"
  runtime       = "python3.12"

  source_path = "${path.module}/src"

  timeout     = 30
  memory_size = 128

  cloudwatch_logs_retention_in_days = 30

  environment_variables = {
    CONTROL_TOPIC     = var.control_topic
    IOT_DATA_ENDPOINT = var.iot_data_endpoint
    AUTH_SECRET_ARN   = var.webhook_auth_secret_arn
    METRICS_NAMESPACE = var.metrics_namespace
    EVENTS_METRIC_NAME = var.events_metric_name
    DEVICE_ID         = var.device_id
  }

  attach_policy_statements = true
  policy_statements = {
    iot_publish = {
      effect    = "Allow"
      actions   = ["iot:Publish"]
      resources = [local.control_topic_arn]
    }

    secrets_read = {
      effect    = "Allow"
      actions   = ["secretsmanager:GetSecretValue"]
      resources = [var.webhook_auth_secret_arn]
    }

    cloudwatch_metrics_write = {
      effect    = "Allow"
      actions   = ["cloudwatch:PutMetricData"]
      resources = ["*"]
    }
  }

  tags = local.tags
}

resource "aws_lambda_permission" "iot_invoke" {
  statement_id  = "AllowExecutionFromIoT"
  action        = "lambda:InvokeFunction"
  function_name = module.lambda.lambda_function_name
  principal     = "iot.amazonaws.com"
  source_arn    = aws_iot_topic_rule.control_events_to_webhook.arn
}

resource "aws_iot_topic_rule" "control_events_to_webhook" {
  name        = replace("${local.name_prefix}control_events_to_webhook", "-", "_")
  description = "Trigger webhook lambda on hardware control events"
  enabled     = true
  sql         = "SELECT * FROM '${var.control_topic}' WHERE event_type = 'buzzer_silence'"
  sql_version = "2016-03-23"

  lambda {
    function_arn = module.lambda.lambda_function_arn
  }

  tags = local.tags
}
