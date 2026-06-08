# ==============================================================
# VARIABLES
# Valores configurables sin tocar el código principal.
# Los valores reales van en terraform.tfvars
# ==============================================================

variable "aws_region" {
  description = "Región de AWS donde se despliega todo"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Prefijo para nombrar todos los recursos (ej: sre-test)"
  type        = string
  default     = "sre-test"
}

variable "vpc_cidr" {
  description = "Rango de IPs de la VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_public_a_cidr" {
  description = "CIDR de la subnet pública en zona A"
  type        = string
  default     = "10.0.1.0/24"
}

variable "subnet_public_b_cidr" {
  description = "CIDR de la subnet pública en zona B"
  type        = string
  default     = "10.0.2.0/24"
}

variable "subnet_private_a_cidr" {
  description = "CIDR de la subnet privada en zona A"
  type        = string
  default     = "10.0.3.0/24"
}

variable "subnet_private_b_cidr" {
  description = "CIDR de la subnet privada en zona B"
  type        = string
  default     = "10.0.4.0/24"
}
