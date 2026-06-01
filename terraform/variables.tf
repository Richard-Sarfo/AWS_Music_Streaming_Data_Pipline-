variable "region" {
  description = "AWS region where all resources are created."
  type        = string
  default     = "us-east-1"
}

variable "env" {
  description = "Deployment environment short name (dev, staging, prod)."
  type        = string
  default     = "dev"
}

variable "project" {
  description = "Project name used as a prefix for resource naming."
  type        = string
  default     = "p1-streaming"
}

variable "alert_email" {
  description = "Email address that receives SNS pipeline failure alerts."
  type        = string
}
