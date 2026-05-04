output "aws_region" {
  value = var.aws_region
}

output "environment" {
  value = var.environment
}

output "api_domain" {
  value = var.domain_name
}

output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  value = aws_subnet.private[*].id
}

output "ecr_repository_url" {
  value = aws_ecr_repository.backend.repository_url
}

output "rds_endpoint" {
  value = aws_db_instance.postgres.address
}

output "db_password_secret_arn" {
  value     = aws_db_instance.postgres.master_user_secret[0].secret_arn
  sensitive = true
}

output "alb_dns_name" {
  value = aws_lb.api.dns_name
}

output "api_url" {
  value = "https://${var.domain_name}"
}

output "ecs_cluster_name" {
  value = aws_ecs_cluster.main.name
}

output "ecs_service_name" {
  value = aws_ecs_service.backend.name
}
