output "vpc_id" {
  description = "ID of the created VPC"
  value       = module.vpc.vpc_id
}

output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = module.compute.alb_dns_name
}

output "application_url" {
  description = "URL to reach the demo application"
  value       = "http://${module.compute.alb_dns_name}"
}
