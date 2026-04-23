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

variable "webhook_lambda_arn" {
  description = "Webhook Lambda ARN"
  type        = string
}

variable "webhook_lambda_name" {
  description = "Webhook Lambda name"
  type        = string
}
