include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "../../../modules/observability"
}

locals {
  use_mock_dependency_outputs = contains(["init", "validate", "plan", "output"], get_terraform_command())
}

dependency "processor" {
  config_path = "../processor"
  skip_outputs = local.use_mock_dependency_outputs

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "output"]
  mock_outputs = {
    lambda_function_name             = "scir-prod-processor"
    lambda_cloudwatch_log_group_name = "/aws/lambda/scir-prod-processor"
  }
}

dependency "webhook" {
  config_path = "../webhook"
  skip_outputs = local.use_mock_dependency_outputs

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "output"]
  mock_outputs = {
    lambda_function_name             = "scir-prod-webhook"
    lambda_cloudwatch_log_group_name = "/aws/lambda/scir-prod-webhook"
  }
}

dependency "messaging" {
  config_path = "../messaging"
  skip_outputs = local.use_mock_dependency_outputs

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "output"]
  mock_outputs = {
    telemetry_queue_name = "scir-prod-washer-telemetry"
  }
}

inputs = {
  processor_lambda_name    = dependency.processor.outputs.lambda_function_name
  processor_log_group_name = dependency.processor.outputs.lambda_cloudwatch_log_group_name
  webhook_lambda_name      = dependency.webhook.outputs.lambda_function_name
  webhook_log_group_name   = dependency.webhook.outputs.lambda_cloudwatch_log_group_name
  telemetry_queue_name     = dependency.messaging.outputs.telemetry_queue_name
  metrics_namespace        = include.root.locals.metrics_namespace
  readings_metric_name     = include.root.locals.readings_metric_name
  events_metric_name       = include.root.locals.events_metric_name
  device_id                = include.root.locals.device_id
}
