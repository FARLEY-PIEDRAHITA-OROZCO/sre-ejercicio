# ==============================================================
# Lambda Handler — Procesamiento de requests con caché Redis
# ==============================================================
# Flujo:
#   1. Recibe request HTTP desde API Gateway (payload v2)
#   2. Genera clave de caché = MD5 del body
#   3. Consulta Redis:
#      - HIT  → retorna valor cacheado + header X-Cache: HIT
#      - MISS → procesa (SHA256), guarda en S3, escribe Redis
#               con TTL 60s, retorna + header X-Cache: MISS
#   4. Cualquier error → HTTP 500 + log a CloudWatch
# ==============================================================

import json
import hashlib
import os
import uuid
import logging
from datetime import datetime, timezone

import redis
import boto3

# ==============================================================
# Configuración de logging
# Los logs aparecen en CloudWatch Logs automáticamente
# ==============================================================

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# ==============================================================
# Variables de entorno (inyectadas desde lambda.tf)
# ==============================================================

REDIS_HOST = os.environ.get("REDIS_HOST", "localhost")
REDIS_PORT = int(os.environ.get("REDIS_PORT", "6379"))
S3_BUCKET  = os.environ.get("S3_BUCKET", "")
REDIS_TTL  = int(os.environ.get("REDIS_TTL", "60"))

# ==============================================================
# Clientes globales (se reusan entre invocaciones del mismo
# entorno de ejecución de Lambda para evitar overhead)
# ==============================================================

s3_client = boto3.client("s3")

redis_client = redis.Redis(
    host=REDIS_HOST,
    port=REDIS_PORT,
    decode_responses=True,         # Redis devuelve strings, no bytes
    socket_connect_timeout=2,      # Timeout de conexión: 2 segundos
    socket_timeout=2               # Timeout de operación: 2 segundos
)


# ==============================================================
# Handler principal
# ==============================================================

def lambda_handler(event, context):
    try:
        # -------------------------------------------------------
        # 1. Extraer el body del request
        # -------------------------------------------------------
        # API Gateway HTTP API (payload v2) envía body como string
        # Si es string, lo codificamos a bytes para hashear

        body = event.get("body", "")
        if body is None:
            body = ""

        if isinstance(body, str):
            body_bytes = body.encode("utf-8")
        else:
            body_bytes = body

        # -------------------------------------------------------
        # 2. Generar clave de caché = MD5 del body
        # -------------------------------------------------------
        # Usamos MD5 por ser rápido y la clave no tiene
        # requisitos criptográficos (solo identificar requests
        # idénticos)

        cache_key = hashlib.md5(body_bytes).hexdigest()
        logger.info(f"Cache key generada: {cache_key}")

        # -------------------------------------------------------
        # 3. Consultar Redis
        # -------------------------------------------------------

        cached_value = redis_client.get(cache_key)

        if cached_value is not None:
            logger.info(f"Cache HIT para key={cache_key}")
            return _build_response(
                status_code=200,
                body=json.loads(cached_value),
                cache_status="HIT"
            )

        # -------------------------------------------------------
        # 4. Cache MISS → procesar y guardar
        # -------------------------------------------------------
        logger.info(f"Cache MISS para key={cache_key}")

        # Transformación del input: SHA256 del body
        processed_output = hashlib.sha256(body_bytes).hexdigest()

        input_str = body if isinstance(body, str) else body.decode("utf-8")

        timestamp = datetime.now(timezone.utc).isoformat()

        result = {
            "input": input_str,
            "output": processed_output,
            "timestamp": timestamp
        }

        # -------------------------------------------------------
        # 5. Guardar resultado en S3
        #    Ruta: results/YYYY/MM/DD/uuid.json
        # -------------------------------------------------------

        fecha = datetime.now(timezone.utc).strftime("%Y/%m/%d")
        s3_key = f"results/{fecha}/{uuid.uuid4()}.json"

        s3_client.put_object(
            Bucket=S3_BUCKET,
            Key=s3_key,
            Body=json.dumps(result, ensure_ascii=False),
            ContentType="application/json"
        )

        logger.info(f"Resultado guardado en s3://{S3_BUCKET}/{s3_key}")

        # -------------------------------------------------------
        # 6. Escribir en Redis con TTL
        #    setex = SET + EXPIRY atómico
        # -------------------------------------------------------

        redis_client.setex(cache_key, REDIS_TTL, json.dumps(result))

        # -------------------------------------------------------
        # 7. Retornar respuesta MISS
        # -------------------------------------------------------

        return _build_response(
            status_code=200,
            body=result,
            cache_status="MISS"
        )

    except Exception as e:
        # -------------------------------------------------------
        # Manejo de errores global
        # Cualquier excepción → HTTP 500
        # Log completo a CloudWatch para debugging
        # -------------------------------------------------------
        logger.error(f"Error procesando request: {str(e)}", exc_info=True)
        return _build_response(
            status_code=500,
            body={"error": f"Error interno del servidor: {str(e)}"},
            cache_status="ERROR"
        )


# ==============================================================
# Helper para construir respuestas HTTP compatibles con
# API Gateway (Lambda Proxy Integration)
# ==============================================================

def _build_response(status_code, body, cache_status):
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type": "application/json",
            "X-Cache": cache_status,
            "Access-Control-Allow-Origin": "*"
        },
        "body": json.dumps(body, ensure_ascii=False)
    }
