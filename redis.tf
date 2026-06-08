# ==============================================================
# ELASTICACHE — SUBNET GROUP
# ==============================================================
# Define en qué subnets puede desplegarse Redis.
# Solo puede vivir en subnets privadas (mismas que Lambda).
# Sin este grupo, ElastiCache no sabe dónde crear el cluster.

resource "aws_elasticache_subnet_group" "main" {
  name        = "${var.project_name}-redis-subnet-group"
  description = "Subnet group para ElastiCache Redis en subnets privadas"
  subnet_ids  = [
    aws_subnet.private_a.id,
    aws_subnet.private_b.id
  ]

  tags = {
    Name = "${var.project_name}-redis-subnet-group"
  }
}

# ==============================================================
# ELASTICACHE — CLUSTER REDIS
# ==============================================================
# Cluster Redis en modo cache (sin persistencia).
# cache.t3.micro: suficiente para el ejercicio, entra en capa gratuita.
# Sin snapshot_retention_limit = sin persistencia en disco.
# Todas las keys deben tener TTL desde Lambda (se maneja en código).
# ==============================================================

resource "aws_elasticache_cluster" "main" {
  cluster_id           = "${var.project_name}-redis"
  engine               = "redis"
  engine_version       = "7.0"
  node_type            = "cache.t3.micro"
  num_cache_nodes      = 1
  port                 = 6379
  subnet_group_name    = aws_elasticache_subnet_group.main.name
  security_group_ids   = [aws_security_group.redis.id]

  # Sin persistencia: no configuramos snapshot_retention_limit
  # (por defecto está en 0 = sin backups automáticos)

  tags = {
    Name = "${var.project_name}-redis"
  }
}
