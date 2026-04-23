include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "../../../modules/api"
}

locals {
  use_mock_dependency_outputs = contains(["init", "validate", "plan", "output"], get_terraform_command())
}

dependency "webhook" {
  config_path = "../webhook"
  skip_outputs = local.use_mock_dependency_outputs

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "output"]
  mock_outputs = {
    lambda_function_arn  = "arn:aws:lambda:eu-central-1:111111111111:function:scir-prod-webhook"
    lambda_function_name = "scir-prod-webhook"
  }
}

inputs = {
  webhook_lambda_arn  = dependency.webhook.outputs.lambda_function_arn
  webhook_lambda_name = dependency.webhook.outputs.lambda_function_name
}
