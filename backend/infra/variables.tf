variable "aws_region" {
  description = "AWS region for staging resources."
  type        = string
  default     = "ap-northeast-2"
}

variable "project" {
  description = "Project name used for resource naming and tags."
  type        = string
  default     = "little-signals"
}

variable "environment" {
  description = "Deployment environment name."
  type        = string
  default     = "staging"
}

variable "domain_name" {
  description = "Fully qualified API domain name for the environment."
  type        = string
}

variable "hosted_zone_name" {
  description = "Route 53 hosted zone name for DNS records."
  type        = string
}

variable "container_image" {
  description = "Container image URI to deploy."
  type        = string
}

variable "app_version" {
  description = "Application version deployed by this infrastructure."
  type        = string
  default     = "0.2.0"
}

variable "db_name" {
  description = "PostgreSQL database name for the application."
  type        = string
  default     = "little_signals_staging"
}

variable "db_username" {
  description = "PostgreSQL database username for the application."
  type        = string
  default     = "little_signals"
}
