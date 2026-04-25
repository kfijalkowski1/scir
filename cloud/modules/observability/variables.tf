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

variable "processor_lambda_name" {
  description = "Processor Lambda name"
  type        = string
}

variable "processor_log_group_name" {
  description = "Processor log group name"
  type        = string
}

variable "webhook_lambda_name" {
  description = "Webhook Lambda name"
  type        = string
}

variable "webhook_log_group_name" {
  description = "Webhook log group name"
  type        = string
}

variable "telemetry_queue_name" {
  description = "Telemetry SQS queue name"
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

variable "device_id" {
  description = "Logical washer device ID"
  type        = string
  default     = "washing-machine"
}
