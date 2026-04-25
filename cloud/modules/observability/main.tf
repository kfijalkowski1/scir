locals {
  prefix         = var.prefix
  name_prefix    = "${local.prefix}${var.environment}-"
  dashboard_name = "${local.name_prefix}washer-observability"
}

resource "aws_cloudwatch_dashboard" "this" {
  dashboard_name = local.dashboard_name

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "Lambda Invocations and Errors"
          region = var.aws_region
          stat   = "Sum"
          period = 300
          metrics = [
            ["AWS/Lambda", "Invocations", "FunctionName", var.processor_lambda_name, { label = "Processor Invocations" }],
            [".", "Errors", ".", ".", { label = "Processor Errors" }],
            ["AWS/Lambda", "Invocations", "FunctionName", var.webhook_lambda_name, { label = "Webhook Invocations" }],
            [".", "Errors", ".", ".", { label = "Webhook Errors" }]
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "Washer Power Reading"
          region = var.aws_region
          stat   = "Maximum"
          period = 60
          metrics = [
            [var.metrics_namespace, var.readings_metric_name, "device_id", var.device_id, { label = "Power (W)" }]
          ]
          yAxis = {
            left = {
              label = "Watts"
            }
          }
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "Event Timeline (Numeric Codes)"
          region = var.aws_region
          stat   = "Maximum"
          period = 60
          metrics = [
            [var.metrics_namespace, var.events_metric_name, "device_id", var.device_id, { label = "Event Code" }]
          ]
          yAxis = {
            left = {
              min   = 0
              max   = 4
              label = "Event code"
            }
          }
          annotations = {
            horizontal = [
              {
                label = "1 = cycle_start"
                value = 1
              },
              {
                label = "2 = cycle_end"
                value = 2
              },
              {
                label = "3 = buzzer_silence"
                value = 3
              }
            ]
          }
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "Telemetry Queue Depth"
          region = var.aws_region
          stat   = "Average"
          period = 300
          metrics = [
            ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", var.telemetry_queue_name]
          ]
        }
      },
      {
        type   = "log"
        x      = 0
        y      = 12
        width  = 24
        height = 7
        properties = {
          title  = "Recent Telemetry and Events"
          region = var.aws_region
          query  = "SOURCE '/aws/lambda/${local.name_prefix}' | filter @log = '${var.processor_log_group_name}' or @log = '${var.webhook_log_group_name}' | fields @timestamp, @message, @log | sort @timestamp desc | limit 100"
          view   = "table"
        }
      },
      {
        type   = "text"
        x      = 0
        y      = 19
        width  = 24
        height = 3
        properties = {
          markdown = "# SCIR Dashboard\\nUse CloudWatch dashboard sharing in AWS Console if you need a public URL."
        }
      }
    ]
  })
}
