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
