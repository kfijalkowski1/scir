variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "prefix" {
  description = "Global resource prefix"
  type        = string
  default     = "scir-"
}

variable "common_tags" {
  description = "Common tags applied to resources"
  type        = map(string)
  default     = {}
}

variable "telemetry_queue_arn" {
  description = "SQS queue ARN used as event source"
  type        = string
}

variable "metrics_namespace" {
  description = "CloudWatch namespace used for telemetry and events"
  type        = string
  default     = "SCIR/Washer"
}

variable "readings_metric_name" {
  description = "CloudWatch metric name for power readings"
  type        = string
  default     = "WasherPowerReading"
}

variable "events_metric_name" {
  description = "CloudWatch metric name for event codes"
  type        = string
  default     = "WasherEventCode"
}

variable "control_topic" {
  description = "Control topic where cycle events are published"
  type        = string
}

variable "iot_data_endpoint" {
  description = "IoT Data-ATS endpoint"
  type        = string
}

variable "discord_webhook_secret_arn" {
  description = "Secrets Manager ARN containing Discord webhook URL"
  type        = string
}

variable "start_power_threshold" {
  description = "Power threshold (W) indicating cycle start"
  type        = number
  default     = 10
}

variable "end_power_threshold" {
  description = "Power threshold (W) for low-power end detection"
  type        = number
  default     = 3
}

variable "low_power_window_seconds" {
  description = "Low-power duration to mark cycle end"
  type        = number
  default     = 180
}

variable "device_id" {
  description = "Logical washer device ID"
  type        = string
  default     = "washing-machine"
}

variable "batch_size" {
  description = "SQS batch size for Lambda event source mapping"
  type        = number
  default     = 100
}

variable "max_batching_window_seconds" {
  description = "Maximum batching window for SQS event source mapping"
  type        = number
  default     = 60
}
