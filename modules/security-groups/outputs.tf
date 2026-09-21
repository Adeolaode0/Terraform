output "alb_sg_id" {
  description = "ID of the ALB security group"
  value       = aws_security_group.alb.id
}

output "instance_sg_id" {
  description = "ID of the EC2 instance security group"
  value       = aws_security_group.instances.id
}
