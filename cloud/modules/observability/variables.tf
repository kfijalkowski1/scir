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
