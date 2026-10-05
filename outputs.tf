output "vpc_id" {
  description = "ID of the created VPC"
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets (ALB placement)"
  value       = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  description = "IDs of the private subnets (instance placement)"
  value       = module.vpc.private_subnet_ids
}

output "alb_sg_id" {
  description = "ID of the Application Load Balancer security group"
  value       = module.security_groups.alb_sg_id
}

output "instance_sg_id" {
  description = "ID of the EC2 instance security group"
  value       = module.security_groups.instance_sg_id
}

output "launch_template_id" {
  description = "ID of the EC2 launch template used by the Auto Scaling group"
  value       = module.compute.launch_template_id
}

output "asg_name" {
  description = "Name of the Auto Scaling group"
  value       = module.compute.asg_name
}

output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = module.compute.alb_dns_name
}

output "application_url" {
  description = "URL to reach the demo application"
  value       = "http://${module.compute.alb_dns_name}"
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic receiving ASG alarm notifications"
  value       = module.compute.sns_topic_arn
}
