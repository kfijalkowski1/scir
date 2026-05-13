locals {
  prefix      = var.prefix
  name_prefix = "${local.prefix}${var.environment}-"
  tags        = merge(var.common_tags, { Service = "api" })
}

module "http_api" {
  source  = "terraform-aws-modules/apigateway-v2/aws"
  version = "~> 6.1"

  name          = "${local.name_prefix}silence-api"
  description   = "SCIR buzzer silence API"
  protocol_type = "HTTP"

  create_domain_name = false

  stage_access_log_settings = {
    create_log_group            = true
    log_group_retention_in_days = 30
    format = jsonencode({
      requestId = "$context.requestId"
      routeKey  = "$context.routeKey"
      status    = "$context.status"
      sourceIp  = "$context.identity.sourceIp"
      error     = "$context.error.message"
    })
  }

  routes = {
    "POST /v1/buzzer/silence" = {
      integration = {
        uri                    = var.webhook_lambda_arn
        payload_format_version = "2.0"
        timeout_milliseconds   = 12000
      }
    }
  }

  tags = local.tags
}

resource "aws_lambda_permission" "allow_apigw" {
  statement_id  = "AllowExecutionFromApiGateway"
  action        = "lambda:InvokeFunction"
  function_name = var.webhook_lambda_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${module.http_api.api_execution_arn}/*/*"
}
