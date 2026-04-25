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

variable "telemetry_topic_filter" {
  description = "MQTT filter for telemetry ingestion"
  type        = string
}

variable "control_topic" {
  description = "MQTT topic for control and user events"
  type        = string
}

variable "telemetry_queue_arn" {
  description = "SQS queue ARN for telemetry buffering"
  type        = string
}

variable "telemetry_queue_url" {
  description = "SQS queue URL for telemetry buffering"
  type        = string
}

variable "shelly_thing_name" {
  description = "Logical suffix for Shelly IoT thing"
  type        = string
  default     = "shelly-plug"
}

variable "esp_thing_name" {
  description = "Logical suffix for ESP32 IoT thing"
  type        = string
  default     = "esp32-buzzer"
}

variable "shelly_publish_topic" {
  description = "Exact telemetry topic Shelly is allowed to publish to"
  type        = string
  default     = ""
}
