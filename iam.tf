# ==============================================================
# IAM — Permisos de Lambda
# ==============================================================
# Lambda necesita un "carné de identidad" (rol) para poder
# hablar con otros servicios AWS: S3, CloudWatch, VPC, etc.
# Principio de mínimo privilegio: solo los permisos necesarios.
# ==============================================================

# --- ROL DE EJECUCIÓN ---
# El rol que Lambda "asume" cuando se ejecuta.
# La política de confianza dice: "Lambda puede asumir este rol".

resource "aws_iam_role" "lambda" {
  name = "${var.project_name}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"  # Solo el servicio Lambda puede asumir este rol
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-lambda-role"
  }
}

# ==============================================================
# POLÍTICA 1 — Permisos sobre S3
# Lambda necesita guardar y leer objetos del bucket de resultados.
# ==============================================================

resource "aws_iam_role_policy" "lambda_s3" {
  name = "${var.project_name}-lambda-s3-policy"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.results.arn,
          "${aws_s3_bucket.results.arn}/*"
        ]
      }
    ]
  })
}

# ==============================================================
# POLÍTICA 2 — Permisos de red (VPC)
# Para que Lambda pueda desplegarse dentro de la VPC,
# necesita permisos para crear y eliminar interfaces de red.
# Sin esto, Lambda no puede arrancar dentro de subnets privadas.
# ==============================================================

resource "aws_iam_role_policy_attachment" "lambda_vpc" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
  # Esta es una política administrada por AWS que incluye:
  # - ec2:CreateNetworkInterface
  # - ec2:DescribeNetworkInterfaces
  # - ec2:DeleteNetworkInterface
  # - logs:CreateLogGroup / CreateLogStream / PutLogEvents (CloudWatch)
}
