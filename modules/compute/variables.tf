variable "environment" {
  description = "Environment name"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC"
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnets for the ALB and Auto Scaling group"
  type        = list(string)
}

variable "alb_sg_id" {
  description = "Security group ID for the ALB"
  type        = string
}

variable "instance_sg_id" {
  description = "Security group ID for the EC2 instances"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type for the Auto Scaling group"
  type        = string
}

variable "min_size" {
  description = "Minimum instances in the Auto Scaling group"
  type        = number
}

variable "max_size" {
  description = "Maximum instances in the Auto Scaling group"
  type        = number
}

variable "desired_capacity" {
  description = "Desired instances in the Auto Scaling group"
  type        = number
}
