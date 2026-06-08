# ==============================================================
# OUTPUTS
# Valores que Terraform muestra al final del apply.
# ==============================================================

output "vpc_id" {
  description = "ID de la VPC creada"
  value       = aws_vpc.main.id
}

output "private_subnet_ids" {
  description = "IDs de las subnets privadas (para Lambda y Redis)"
  value       = [aws_subnet.private_a.id, aws_subnet.private_b.id]
}

output "api_endpoint" {
  description = "URL completa del API Gateway para hacer curl"
  value       = aws_apigatewayv2_api.main.api_endpoint
}

output "lambda_function_name" {
  description = "Nombre de la función Lambda (útil para ver logs)"
  value       = aws_lambda_function.main.function_name
}

output "s3_bucket_name" {
  description = "Nombre del bucket S3 de resultados"
  value       = aws_s3_bucket.results.bucket
}

output "redis_endpoint" {
  description = "Endpoint del cluster Redis (para debugging)"
  value       = aws_elasticache_cluster.main.cache_nodes[0].address
}
