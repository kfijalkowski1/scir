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

variable "control_topic" {
  description = "Control topic used to silence the buzzer"
  type        = string
}

variable "iot_data_endpoint" {
  description = "IoT Data-ATS endpoint"
  type        = string
}

variable "webhook_auth_secret_arn" {
  description = "Secrets Manager ARN containing shared auth token"
  type        = string
}

variable "device_id" {
  description = "Logical washer device ID"
  type        = string
  default     = "washing-machine"
}
