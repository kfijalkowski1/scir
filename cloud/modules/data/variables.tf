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

variable "readings_table_name" {
  description = "Logical suffix for readings table"
  type        = string
  default     = "washer-readings"
}

variable "events_table_name" {
  description = "Logical suffix for events table"
  type        = string
  default     = "washer-events"
}

variable "memory_retention_hours" {
  description = "Timestream memory retention"
  type        = number
  default     = 24
}

variable "magnetic_retention_days" {
  description = "Timestream magnetic retention"
  type        = number
  default     = 365
}

variable "discord_webhook_secret_name" {
  description = "Secrets Manager name suffix for Discord webhook secret"
  type        = string
  default     = "discord-webhook"
}

variable "webhook_auth_secret_name" {
  description = "Secrets Manager name suffix for API auth token secret"
  type        = string
  default     = "webhook-auth-token"
}

variable "discord_webhook_url" {
  description = "Discord webhook URL. Empty string skips writing secret value."
  type        = string
  default     = ""
  sensitive   = true
}

variable "webhook_auth_token" {
  description = "Shared API auth token. Empty string skips writing secret value."
  type        = string
  default     = ""
  sensitive   = true
}
