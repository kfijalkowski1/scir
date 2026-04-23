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
  events_rule_name    = replace("${local.name_prefix}control_to_timestream", "-", "_")
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
        Resource = "arn:aws:iot:${var.aws_region}:${data.aws_caller_identity.current.account_id}:client/${aws_iot_thing.shelly.name}"
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
        Resource = "arn:aws:iot:${var.aws_region}:${data.aws_caller_identity.current.account_id}:client/${aws_iot_thing.esp.name}"
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

resource "aws_iam_role" "events_rule" {
  name = "${local.name_prefix}iot-events-rule"

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

resource "aws_iam_role_policy" "events_rule" {
  name = "${local.name_prefix}iot-events-rule"
  role = aws_iam_role.events_rule.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "timestream:WriteRecords",
          "timestream:DescribeEndpoints"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iot_topic_rule" "control_to_timestream" {
  name        = local.events_rule_name
  description = "Persist buzzer and silence events from control topic"
  enabled     = true
  sql         = "SELECT event_type, source, device_id, ts AS event_ts, 1 AS event_value FROM '${var.control_topic}'"
  sql_version = "2016-03-23"

  timestream {
    role_arn      = aws_iam_role.events_rule.arn
    database_name = var.timestream_database_name
    table_name    = var.timestream_events_table_name

    dimension {
      name  = "event_type"
      value = "$${event_type}"
    }

    dimension {
      name  = "source"
      value = "$${source}"
    }

    dimension {
      name  = "device_id"
      value = "$${device_id}"
    }

    timestamp {
      unit  = "MILLISECONDS"
      value = "$${event_ts}"
    }
  }

  tags = local.tags
}
