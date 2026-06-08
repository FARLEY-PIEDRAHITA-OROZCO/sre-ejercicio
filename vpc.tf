# ==============================================================
# VPC PRINCIPAL
# ==============================================================
# La red privada de toda la infraestructura.
# Todos los recursos (Lambda, Redis) vivirán dentro de esta VPC.

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true   # Necesario para que Lambda resuelva nombres DNS (ej: endpoint de Redis)
  enable_dns_hostnames = true   # Necesario para el VPC Endpoint de S3

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

# ==============================================================
# SUBNETS PÚBLICAS
# (Aquí vive el NAT Gateway)
# ==============================================================

resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.subnet_public_a_cidr
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true  # Los recursos aquí reciben IP pública automáticamente

  tags = {
    Name = "${var.project_name}-subnet-public-a"
  }
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.subnet_public_b_cidr
  availability_zone       = "${var.aws_region}b"
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-subnet-public-b"
  }
}

# ==============================================================
# SUBNETS PRIVADAS
# (Aquí viven Lambda y Redis — sin acceso directo desde internet)
# ==============================================================

resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.subnet_private_a_cidr
  availability_zone = "${var.aws_region}a"

  tags = {
    Name = "${var.project_name}-subnet-private-a"
  }
}

resource "aws_subnet" "private_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.subnet_private_b_cidr
  availability_zone = "${var.aws_region}b"

  tags = {
    Name = "${var.project_name}-subnet-private-b"
  }
}

# ==============================================================
# INTERNET GATEWAY
# La puerta de entrada/salida entre la VPC e internet.
# Solo las subnets públicas tienen ruta hacia aquí.
# ==============================================================

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

# ==============================================================
# NAT GATEWAY
# Permite que Lambda (en subnet privada) salga a internet,
# pero bloquea cualquier conexión entrante desde afuera.
# Requiere una IP elástica (EIP) fija.
# ==============================================================

resource "aws_eip" "nat" {
  domain = "vpc"  # Tipo de IP: pertenece a la VPC (no a una instancia EC2)

  tags = {
    Name = "${var.project_name}-nat-eip"
  }
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id           # La IP pública fija que usará
  subnet_id     = aws_subnet.public_a.id   # Vive en la subnet pública A

  # El NAT Gateway debe crearse DESPUÉS del Internet Gateway
  depends_on = [aws_internet_gateway.main]

  tags = {
    Name = "${var.project_name}-nat-gw"
  }
}

# ==============================================================
# TABLAS DE RUTAS
# Definen por dónde sale el tráfico de cada subnet.
# Subnet pública → Internet Gateway (tráfico directo a internet)
# Subnet privada → NAT Gateway (tráfico de salida solo)
# ==============================================================

# --- Tabla de rutas para subnets PÚBLICAS ---
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"                    # Todo el tráfico externo...
    gateway_id = aws_internet_gateway.main.id    # ...sale por el Internet Gateway
  }

  tags = {
    Name = "${var.project_name}-rt-public"
  }
}

# Asociar tabla pública a subnet pública A
resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

# Asociar tabla pública a subnet pública B
resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}

# --- Tabla de rutas para subnets PRIVADAS ---
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"                # Todo el tráfico externo...
    nat_gateway_id = aws_nat_gateway.main.id     # ...sale por el NAT Gateway (no directamente)
  }

  tags = {
    Name = "${var.project_name}-rt-private"
  }
}

# Asociar tabla privada a subnet privada A
resource "aws_route_table_association" "private_a" {
  subnet_id      = aws_subnet.private_a.id
  route_table_id = aws_route_table.private.id
}

# Asociar tabla privada a subnet privada B
resource "aws_route_table_association" "private_b" {
  subnet_id      = aws_subnet.private_b.id
  route_table_id = aws_route_table.private.id
}

# ==============================================================
# VPC ENDPOINT — S3 (tipo Gateway)
# Tráfico entre Lambda y S3 nunca sale a internet.
# Va directo por la red interna de AWS — más seguro y rápido.
# ==============================================================

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"  # Tipo Gateway: gratis, solo para S3 y DynamoDB

  # Se asocia a las tablas de rutas privadas para que Lambda lo use automáticamente
  route_table_ids = [aws_route_table.private.id]

  tags = {
    Name = "${var.project_name}-vpce-s3"
  }
}

# ==============================================================
# SECURITY GROUPS
# Vigilantes en cada puerta: definen quién puede hablar con quién.
# ==============================================================

# --- Security Group de Lambda ---
# Lambda puede salir a cualquier lado (para llamar a Redis y S3),
# pero nadie puede entrar directamente a Lambda.
resource "aws_security_group" "lambda" {
  name        = "${var.project_name}-sg-lambda"
  description = "Security Group para Lambda — permite salida a Redis y S3"
  vpc_id      = aws_vpc.main.id

  # Tráfico de SALIDA: Lambda puede conectarse a cualquier destino
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"          # -1 significa "todos los protocolos"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-sg-lambda"
  }
}

# --- Security Group de Redis ---
# Redis SOLO acepta conexiones en el puerto 6379
# y SOLO si vienen del Security Group de Lambda.
resource "aws_security_group" "redis" {
  name        = "${var.project_name}-sg-redis"
  description = "Security Group para Redis — solo acepta Lambda en puerto 6379"
  vpc_id      = aws_vpc.main.id

  # Tráfico de ENTRADA: solo Lambda, solo puerto 6379
  ingress {
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.lambda.id]  # Solo desde el SG de Lambda
  }

  # Tráfico de SALIDA: Redis puede responder a Lambda
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-sg-redis"
  }
}
