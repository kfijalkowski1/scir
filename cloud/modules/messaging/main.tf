data "aws_caller_identity" "current" {}

locals {
  prefix      = var.prefix
  name_prefix = "${local.prefix}${var.environment}-"
  tags        = merge(var.common_tags, { Service = "messaging" })

  topic_prefix_segment = trimsuffix(var.prefix, "-")
  default_telemetry    = "${local.topic_prefix_segment}/${var.environment}/washer/+/status/switch:0"
  default_control      = "${local.topic_prefix_segment}/${var.environment}/washer/buzzer/events"

  resolved_telemetry_topic_filter = var.telemetry_topic_filter != "" ? var.telemetry_topic_filter : local.default_telemetry
  resolved_control_topic          = var.control_topic != "" ? var.control_topic : local.default_control
}

module "telemetry_queue" {
  source  = "terraform-aws-modules/sqs/aws"
  version = "~> 5.2"

  name = "${local.name_prefix}${var.telemetry_queue_name}"

  create_dlq = true
  redrive_policy = {
    maxReceiveCount = 5
  }

  sqs_managed_sse_enabled = true

  visibility_timeout_seconds = 120
  receive_wait_time_seconds  = 20

  create_queue_policy = true
  queue_policy_statements = {
    iot_publish = {
      sid     = "AllowIoTRulePublish"
      actions = ["sqs:SendMessage"]

      principals = [
        {
          type        = "Service"
          identifiers = ["iot.amazonaws.com"]
        }
      ]

      condition = [
        {
          test     = "StringEquals"
          variable = "aws:SourceAccount"
          values   = [data.aws_caller_identity.current.account_id]
        }
      ]
    }
  }

  tags = local.tags
}
