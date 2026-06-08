# ==============================================================
# S3 BUCKET — Almacenamiento de resultados
# ==============================================================
# Guarda los resultados procesados por Lambda.
# Completamente privado — solo Lambda puede acceder via IAM.
# El tráfico nunca sale a internet gracias al VPC Endpoint.
# ==============================================================

resource "aws_s3_bucket" "results" {
  bucket        = "${var.project_name}-results-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
  # Incluimos el account_id para garantizar nombre único global en S3

  tags = {
    Name = "${var.project_name}-results"
  }
}

# ==============================================================
# BLOQUEAR TODO ACCESO PÚBLICO
# Las 4 configuraciones requeridas por el ejercicio.
# Esto previene que alguien exponga accidentalmente el bucket.
# ==============================================================

resource "aws_s3_bucket_public_access_block" "results" {
  bucket = aws_s3_bucket.results.id

  block_public_acls       = true  # Bloquea ACLs públicas nuevas y existentes
  block_public_policy     = true  # Bloquea políticas que den acceso público
  ignore_public_acls      = true  # Ignora ACLs públicas aunque existan
  restrict_public_buckets = true  # Restringe acceso público aunque haya política
}

# ==============================================================
# VERSIONADO
# Guarda el historial de cada objeto.
# Si Lambda sobreescribe un resultado, el anterior se conserva.
# ==============================================================

resource "aws_s3_bucket_versioning" "results" {
  bucket = aws_s3_bucket.results.id

  versioning_configuration {
    status = "Enabled"
  }
}

# ==============================================================
# BUCKET POLICY
# Define explícitamente quién puede hacer qué en el bucket.
# Solo el rol IAM de Lambda tiene permisos — nadie más.
# ==============================================================

resource "aws_s3_bucket_policy" "results" {
  bucket = aws_s3_bucket.results.id

  # depends_on necesario: la policy no puede aplicarse
  # si el bloqueo público aún no está activo
  depends_on = [aws_s3_bucket_public_access_block.results]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowLambdaAccess"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.lambda.arn  # Solo el rol de Lambda
        }
        Action = [
          "s3:PutObject",    # Lambda puede guardar objetos
          "s3:GetObject",    # Lambda puede leer objetos
          "s3:ListBucket"    # Lambda puede listar el contenido
        ]
        Resource = [
          aws_s3_bucket.results.arn,           # El bucket en sí (para ListBucket)
          "${aws_s3_bucket.results.arn}/*"     # Todos los objetos dentro
        ]
      }
    ]
  })
}

# ==============================================================
# DATA SOURCE — cuenta AWS actual
# Usamos el account_id para garantizar nombre único del bucket
# y para referenciar el ARN del rol Lambda en la policy.
# ==============================================================

data "aws_caller_identity" "current" {}
