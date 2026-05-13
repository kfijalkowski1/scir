include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "../../../modules/iot-core"
}

locals {
  use_mock_dependency_outputs = contains(["validate"], get_terraform_command())
}

dependency "messaging" {
  config_path = "../messaging"
  skip_outputs = local.use_mock_dependency_outputs

  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
  mock_outputs = {
    telemetry_queue_arn    = "arn:aws:sqs:eu-central-1:111111111111:scir-prod-washer-telemetry"
    telemetry_queue_url    = "https://sqs.eu-central-1.amazonaws.com/111111111111/scir-prod-washer-telemetry"
    telemetry_queue_name   = "scir-prod-washer-telemetry"
    telemetry_topic_filter = "scir/prod/washer/+/status/switch:0"
    control_topic          = "scir/prod/washer/buzzer/events"
  }
}

inputs = {
  telemetry_topic_filter = dependency.messaging.outputs.telemetry_topic_filter
  control_topic          = dependency.messaging.outputs.control_topic
  telemetry_queue_arn    = dependency.messaging.outputs.telemetry_queue_arn
  telemetry_queue_url    = dependency.messaging.outputs.telemetry_queue_url
  metrics_namespace      = include.root.locals.metrics_namespace
  events_metric_name     = include.root.locals.events_metric_name
}
