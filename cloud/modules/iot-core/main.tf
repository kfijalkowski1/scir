data "aws_caller_identity" "current" {}

data "aws_iot_endpoint" "data_ats" {
  endpoint_type = "iot:Data-ATS"
}

locals {
  prefix      = var.prefix
  name_prefix = "${local.prefix}${var.environment}-"
  tags        = merge(var.common_tags, { Service = "iot-core" })

  topic_prefix_segment = trimsuffix(var.prefix, "-")
  shelly_topic_default = "${local.topic_prefix_segment}/${var.environment}/washer/shelly-plug/status/switch:0"
  shelly_topic         = var.shelly_publish_topic != "" ? var.shelly_publish_topic : local.shelly_topic_default

  telemetry_rule_name = replace("${local.name_prefix}telemetry_to_sqs", "-", "_")
}

resource "aws_iot_thing" "shelly" {
  name = "${local.name_prefix}${var.shelly_thing_name}"

  attributes = {
    role = "telemetry-publisher"
  }
}

resource "aws_iot_thing" "esp" {
  name = "${local.name_prefix}${var.esp_thing_name}"

  attributes = {
    role = "buzzer-device"
  }
}

resource "aws_iot_certificate" "shelly" {
  active = true
}

resource "aws_iot_certificate" "esp" {
  active = true
}

resource "aws_iot_policy" "shelly" {
  name = replace("${local.name_prefix}shelly_policy", "-", "_")

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["iot:Connect"]
        Resource = "arn:aws:iot:${var.aws_region}:${data.aws_caller_identity.current.account_id}:client/$${iot:Connection.Thing.ThingName}"
      },
      {
        Effect   = "Allow"
        Action   = ["iot:Publish"]
        Resource = "arn:aws:iot:${var.aws_region}:${data.aws_caller_identity.current.account_id}:topic/${local.shelly_topic}"
      }
    ]
  })

  tags = local.tags
}

resource "aws_iot_policy" "esp" {
  name = replace("${local.name_prefix}esp_policy", "-", "_")

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["iot:Connect"]
        Resource = "arn:aws:iot:${var.aws_region}:${data.aws_caller_identity.current.account_id}:client/$${iot:Connection.Thing.ThingName}"
      },
      {
        Effect   = "Allow"
        Action   = ["iot:Publish"]
        Resource = "arn:aws:iot:${var.aws_region}:${data.aws_caller_identity.current.account_id}:topic/${var.control_topic}"
      },
      {
        Effect   = "Allow"
        Action   = ["iot:Subscribe"]
        Resource = "arn:aws:iot:${var.aws_region}:${data.aws_caller_identity.current.account_id}:topicfilter/${var.control_topic}"
      },
      {
        Effect   = "Allow"
        Action   = ["iot:Receive"]
        Resource = "arn:aws:iot:${var.aws_region}:${data.aws_caller_identity.current.account_id}:topic/${var.control_topic}"
      }
    ]
  })

  tags = local.tags
}

resource "aws_iot_policy_attachment" "shelly" {
  policy = aws_iot_policy.shelly.name
  target = aws_iot_certificate.shelly.arn
}

resource "aws_iot_policy_attachment" "esp" {
  policy = aws_iot_policy.esp.name
  target = aws_iot_certificate.esp.arn
}

resource "aws_iot_thing_principal_attachment" "shelly" {
  thing     = aws_iot_thing.shelly.name
  principal = aws_iot_certificate.shelly.arn
}

resource "aws_iot_thing_principal_attachment" "esp" {
  thing     = aws_iot_thing.esp.name
  principal = aws_iot_certificate.esp.arn
}

resource "aws_iam_role" "telemetry_rule" {
  name = "${local.name_prefix}iot-telemetry-rule"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "iot.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = local.tags
}

resource "aws_iam_role_policy" "telemetry_rule" {
  name = "${local.name_prefix}iot-telemetry-rule"
  role = aws_iam_role.telemetry_rule.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["sqs:SendMessage"]
        Resource = var.telemetry_queue_arn
      }
    ]
  })
}

resource "random_password" "shelly_mqtt" {
  length  = 32
  special = false
}

module "shelly_authorizer_lambda" {
  source  = "terraform-aws-modules/lambda/aws"
  version = "~> 8.8"

  function_name = "${local.name_prefix}shelly-authorizer"
  description   = "MQTT custom authorizer for Shelly plug: validates username/password"
  handler       = "handler.lambda_handler"
  runtime       = "python3.12"
  source_path   = "${path.module}/src/authorizer"
  timeout       = 5
  memory_size   = 128

  cloudwatch_logs_retention_in_days = 30

  environment_variables = {
    EXPECTED_USERNAME = aws_iot_thing.shelly.name
    EXPECTED_PASSWORD = random_password.shelly_mqtt.result
    ACCOUNT_ID        = data.aws_caller_identity.current.account_id
    AWS_REGION_NAME   = var.aws_region
    THING_NAME        = aws_iot_thing.shelly.name
    PUBLISH_TOPIC     = local.shelly_topic
  }

  tags = local.tags
}

resource "aws_lambda_permission" "iot_invoke_shelly_authorizer" {
  statement_id  = "AllowIoTCustomAuthorizer"
  action        = "lambda:InvokeFunction"
  function_name = module.shelly_authorizer_lambda.lambda_function_name
  principal     = "iot.amazonaws.com"
  source_arn    = aws_iot_authorizer.shelly.arn
}

resource "aws_iot_authorizer" "shelly" {
  name                    = "${local.name_prefix}shelly-authorizer"
  authorizer_function_arn = module.shelly_authorizer_lambda.lambda_function_arn
  signing_disabled        = true
  status                  = var.shelly_auth_mode == "basic" ? "ACTIVE" : "INACTIVE"

  tags = local.tags
}

# Dedicated domain configuration so Shelly can connect on port 8883 without a
# client certificate. The default authorizer is invoked for every unauthenticated
# connection, removing the need for a query string in the MQTT username.
resource "aws_iot_domain_configuration" "shelly_basic_auth" {
  count                = var.shelly_auth_mode == "basic" ? 1 : 0
  name                 = "${local.name_prefix}shelly-basic-auth"
  status               = "ENABLED"
  authentication_type  = "CUSTOM_AUTH"
  application_protocol = "SECURE_MQTT"

  authorizer_config {
    default_authorizer_name   = aws_iot_authorizer.shelly.name
    allow_authorizer_override = false
  }

  tags = local.tags
}

resource "aws_iot_topic_rule" "telemetry_to_sqs" {
  name        = local.telemetry_rule_name
  description = "Buffer Shelly telemetry in SQS for batched Lambda processing"
  enabled     = true
  sql         = "SELECT *, topic() AS mqtt_topic, timestamp() AS ingest_ts FROM '${var.telemetry_topic_filter}'"
  sql_version = "2016-03-23"

  sqs {
    queue_url  = var.telemetry_queue_url
    role_arn   = aws_iam_role.telemetry_rule.arn
    use_base64 = false
  }

  tags = local.tags
}
