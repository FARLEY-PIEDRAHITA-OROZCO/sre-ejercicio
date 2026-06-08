# ==============================================================
# API GATEWAY — HTTP API (v2)
# ==============================================================
# Decisión: HTTP API en vez de REST API.
# Justificación:
#   - HTTP API es ~71% más barato
#   - Menor latencia (sin transformaciones request/response)
#   - Soporta integración proxy con Lambda de forma nativa
#   - Para un endpoint POST sin autenticación IAM ni
#     transformaciones avanzadas, es la opción correcta
# ==============================================================

# ---------------------------------------------------------------
# 1. HTTP API
# ---------------------------------------------------------------

resource "aws_apigatewayv2_api" "main" {
  name          = "${var.project_name}-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["POST", "OPTIONS"]
    allow_headers = ["Content-Type"]
  }

  tags = {
    Name = "${var.project_name}-api"
  }
}

# ---------------------------------------------------------------
# 2. Integración Lambda (AWS_PROXY)
# ---------------------------------------------------------------
# AWS_PROXY: pasa el request completo a Lambda sin modificar.
# payload v2: formato más ligero que v1, específico de HTTP API.

resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.main.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.main.invoke_arn
  payload_format_version = "2.0"
}

# ---------------------------------------------------------------
# 3. Ruta POST /process
# ---------------------------------------------------------------

resource "aws_apigatewayv2_route" "post_process" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "POST /process"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

# ---------------------------------------------------------------
# 4. Stage por defecto con throttling y access logs
# ---------------------------------------------------------------

resource "aws_cloudwatch_log_group" "api_gateway" {
  name              = "/aws/apigateway/${var.project_name}"
  retention_in_days = 7

  tags = {
    Name = "${var.project_name}-apigw-logs"
  }
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.main.id
  name        = "$default"
  auto_deploy = true

  # Throttling: protege el backend de picos de tráfico
  default_route_settings {
    throttling_burst_limit = 100
    throttling_rate_limit  = 50
  }

  # Access logs: registra cada request para debugging
  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      ip             = "$context.identity.sourceIp"
      requestTime    = "$context.requestTime"
      httpMethod     = "$context.httpMethod"
      routeKey       = "$context.routeKey"
      status         = "$context.status"
      protocol       = "$context.protocol"
      responseLength = "$context.responseLength"
    })
  }

  tags = {
    Name = "${var.project_name}-api-stage"
  }
}

# ---------------------------------------------------------------
# 5. Permiso para que API Gateway invoque Lambda
# ---------------------------------------------------------------

resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.main.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*/*"
}
