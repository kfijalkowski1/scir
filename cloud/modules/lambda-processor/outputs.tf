output "lambda_function_arn" {
  description = "Processor Lambda ARN"
  value       = module.lambda.lambda_function_arn
}

output "lambda_function_name" {
  description = "Processor Lambda function name"
  value       = module.lambda.lambda_function_name
}

output "lambda_cloudwatch_log_group_name" {
  description = "Processor Lambda CloudWatch log group"
  value       = module.lambda.lambda_cloudwatch_log_group_name
}
