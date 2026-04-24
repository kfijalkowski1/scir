include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "../../../modules/lambda-processor"
}

locals {
  use_mock_dependency_outputs = contains(["init", "validate", "plan", "output"], get_terraform_command())
}

dependency "data" {
  config_path = "../data"
  skip_outputs = local.use_mock_dependency_outputs

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "output"]
  mock_outputs = {
    timestream_database_name   = "scir_prod_washer"
    readings_table_name        = "scir_prod_washer_readings"
    events_table_name          = "scir_prod_washer_events"
    discord_webhook_secret_arn = "arn:aws:secretsmanager:eu-central-1:111111111111:secret:mock"
  }
}

dependency "messaging" {
  config_path = "../messaging"
  skip_outputs = local.use_mock_dependency_outputs

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "output"]
  mock_outputs = {
    telemetry_queue_arn = "arn:aws:sqs:eu-central-1:111111111111:scir-prod-washer-telemetry"
    control_topic       = "scir/prod/washer/buzzer/events"
  }
}

dependency "iot" {
  config_path = "../iot"
  skip_outputs = local.use_mock_dependency_outputs

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "output"]
  mock_outputs = {
    iot_data_endpoint = "a0000000000000-ats.iot.eu-central-1.amazonaws.com"
  }
}

inputs = {
  telemetry_queue_arn            = dependency.messaging.outputs.telemetry_queue_arn
  control_topic                  = dependency.messaging.outputs.control_topic
  iot_data_endpoint              = dependency.iot.outputs.iot_data_endpoint
  timestream_database_name       = dependency.data.outputs.timestream_database_name
  timestream_readings_table_name = dependency.data.outputs.readings_table_name
  timestream_events_table_name   = dependency.data.outputs.events_table_name
  discord_webhook_secret_arn     = dependency.data.outputs.discord_webhook_secret_arn
}
