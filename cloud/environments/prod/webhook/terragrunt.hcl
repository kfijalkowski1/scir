include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "../../../modules/lambda-webhook"
}

locals {
  use_mock_dependency_outputs = contains(["init", "validate", "plan", "output"], get_terraform_command())
}

dependency "data" {
  config_path = "../data"
  skip_outputs = local.use_mock_dependency_outputs

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "output"]
  mock_outputs = {
    webhook_auth_secret_arn = "arn:aws:secretsmanager:eu-central-1:111111111111:secret:mock"
  }
}

dependency "messaging" {
  config_path = "../messaging"
  skip_outputs = local.use_mock_dependency_outputs

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "output"]
  mock_outputs = {
    control_topic = "scir/prod/washer/buzzer/events"
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
  control_topic           = dependency.messaging.outputs.control_topic
  iot_data_endpoint       = dependency.iot.outputs.iot_data_endpoint
  webhook_auth_secret_arn = dependency.data.outputs.webhook_auth_secret_arn
}
