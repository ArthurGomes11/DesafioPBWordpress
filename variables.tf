variable "env" {
  description = "Nome do ambiente (ex: dev, prod) para nomear os recursos."
  type        = string
  default     = "dev"
}


variable "vpc_cidr" {
  description = "Bloco CIDR para a VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "db_user" {
  description = "Nome de usuário para o banco de dados RDS."
  type        = string
}

variable "db_password" {
  description = "Senha para o banco de dados RDS."
  type        = string
  sensitive   = true
}

variable "db_name" {
  description = "Nome do banco de dados no RDS."
  type        = string
  default     = "wordpressdb"
}

variable "aws_profile" {
  description = "Nome do perfil de credenciais da AWS a ser utilizado."
  type        = string
  default     = "default"
}
