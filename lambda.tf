# ==============================================================
# LAMBDA — FUNCIÓN + DEPENDENCIAS (REDIS LAYER)
# ==============================================================
# Estrategia:
#   - Lambda Layer para redis (no está en el runtime estándar)
#   - null_resource con local-exec instala redis vía pip y
#     empaqueta el zip automáticamente durante terraform apply
#   - archive_file para el código de la función (excluye layer/)
# ==============================================================

# ---------------------------------------------------------------
# 1. Empaquetar dependencia redis en un Lambda Layer
# ---------------------------------------------------------------

resource "null_resource" "install_lambda_deps" {
  # Triggers: solo se reinstala si cambia el contenido de requirements.txt
  triggers = {
    deps_hash = filemd5("${path.module}/lambda/requirements.txt")
  }

  # pip install redis dentro de lambda/layer/python/
  # y comprime todo en redis_layer.zip para el Lambda Layer
  # NOTA: PowerShell acepta forward slashes en rutas, compatibles con path.module
  provisioner "local-exec" {
    command = "pip install redis -q -t \"${path.module}/lambda/layer/python/\"; Compress-Archive -Path \"${path.module}/lambda/layer/*\" -DestinationPath \"${path.module}/redis_layer.zip\" -Force"
    interpreter = ["PowerShell", "-Command"]
  }
}

# ---------------------------------------------------------------
# 2. Lambda Layer — redis
# ---------------------------------------------------------------

resource "aws_lambda_layer_version" "redis_layer" {
  filename            = "${path.module}/redis_layer.zip"
  layer_name          = "${var.project_name}-redis-layer"
  compatible_runtimes = ["python3.12"]

  depends_on = [null_resource.install_lambda_deps]
}

# ---------------------------------------------------------------
# 3. Empaquetar código de la función Lambda
# ---------------------------------------------------------------

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda/"
  output_path = "${path.module}/lambda_function.zip"
  excludes    = ["layer/"]
}

# ---------------------------------------------------------------
# 4. Función Lambda
# ---------------------------------------------------------------

resource "aws_lambda_function" "main" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "${var.project_name}-processor"
  role             = aws_iam_role.lambda.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.12"
  timeout          = 30
  memory_size      = 256
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  # Capa con la librería redis
  layers = [aws_lambda_layer_version.redis_layer.arn]

  # Lambda dentro de la VPC, en subnets privadas
  vpc_config {
    subnet_ids         = [aws_subnet.private_a.id, aws_subnet.private_b.id]
    security_group_ids = [aws_security_group.lambda.id]
  }

  # Variables de entorno para conectar a Redis y S3
  environment {
    variables = {
      REDIS_HOST = aws_elasticache_cluster.main.cache_nodes[0].address
      REDIS_PORT = "6379"
      S3_BUCKET  = aws_s3_bucket.results.bucket
      REDIS_TTL  = "60"
    }
  }

  # Dependencias explícitas para garantizar orden correcto
  depends_on = [
    aws_cloudwatch_log_group.lambda,
    null_resource.install_lambda_deps
  ]

  tags = {
    Name = "${var.project_name}-processor"
  }
}

# ---------------------------------------------------------------
# 5. CloudWatch Log Group para Lambda
# ---------------------------------------------------------------

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${var.project_name}-processor"
  retention_in_days = 7

  tags = {
    Name = "${var.project_name}-lambda-logs"
  }
}
