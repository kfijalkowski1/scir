locals {
  aws_region  = "eu-central-1"
  environment = "prod"
  prefix      = "scir-"

  # Set this env var before first apply to ensure a globally unique S3 bucket name.
  state_suffix          = "scir26l"
  state_bucket_name     = "${local.prefix}tofu-state-${local.state_suffix}-${local.aws_region}"

  topic_prefix_segment   = trimsuffix(local.prefix, "-")
  washer_topic_root      = "washer"
  telemetry_topic_filter = "${local.topic_prefix_segment}/${local.environment}/${local.washer_topic_root}/+/status/switch:0"
  control_topic          = "${local.topic_prefix_segment}/${local.environment}/${local.washer_topic_root}/buzzer/events"

  common_tags = {
    Project     = "scir"
    Environment = local.environment
    ManagedBy   = "terragrunt"
  }
}

remote_state {
  backend = "s3"

  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }

  config = {
    bucket       = local.state_bucket_name
    key          = "${path_relative_to_include()}/tofu.tfstate"
    region       = local.aws_region
    encrypt      = true
    use_lockfile = true

    s3_bucket_tags = local.common_tags
  }
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
provider "aws" {
  region = "${local.aws_region}"

  default_tags {
    tags = ${jsonencode(local.common_tags)}
  }
}
EOF
}

inputs = {
  aws_region  = local.aws_region
  environment = local.environment
  prefix      = local.prefix
  common_tags = local.common_tags
}
