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

variable "rds_deletion_protection" {
  description = "Whether to enable RDS deletion protection. The default is for disposable staging; production must override this to true."
  type        = bool
  default     = false
}

variable "rds_skip_final_snapshot" {
  description = "Whether to skip the final RDS snapshot on deletion. The default is for disposable staging; production must override this to false."
  type        = bool
  default     = true
}

variable "rds_apply_immediately" {
  description = "Whether RDS modifications apply immediately. The default is for disposable staging; production must override this to false."
  type        = bool
  default     = true
}

variable "alert_email" {
  description = "Email address to subscribe to the alerts SNS topic. Subscription is auto-confirmed by clicking the confirmation link AWS sends."
  type        = string
}

variable "gha_repo_full_name" {
  description = "GitHub repository in <owner>/<repo> form, used to scope the GHA OIDC trust policy."
  type        = string
}
