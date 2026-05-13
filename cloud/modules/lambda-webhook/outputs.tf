output "lambda_function_arn" {
  description = "Webhook Lambda ARN"
  value       = module.lambda.lambda_function_arn
}

output "lambda_function_name" {
  description = "Webhook Lambda function name"
  value       = module.lambda.lambda_function_name
}

output "lambda_cloudwatch_log_group_name" {
  description = "Webhook Lambda CloudWatch log group"
  value       = module.lambda.lambda_cloudwatch_log_group_name
}
