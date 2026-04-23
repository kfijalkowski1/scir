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

variable "telemetry_queue_name" {
  description = "Logical suffix for telemetry SQS queue"
  type        = string
  default     = "washer-telemetry"
}

variable "telemetry_topic_filter" {
  description = "MQTT telemetry topic filter"
  type        = string
  default     = ""
}

variable "control_topic" {
  description = "MQTT control/event topic"
  type        = string
  default     = ""
}
