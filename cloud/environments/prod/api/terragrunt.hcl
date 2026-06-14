include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "../../../modules/api"
}

locals {
  use_mock_dependency_outputs = contains(["validate"], get_terraform_command())
}

dependency "webhook" {
  config_path = "../webhook"
  skip_outputs = local.use_mock_dependency_outputs

  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
  mock_outputs = {
    lambda_function_arn  = "arn:aws:lambda:eu-central-1:111111111111:function:scir-prod-webhook"
    lambda_function_name = "scir-prod-webhook"
  }
}

inputs = {
  webhook_lambda_arn  = dependency.webhook.outputs.lambda_function_arn
  webhook_lambda_name = dependency.webhook.outputs.lambda_function_name
}
