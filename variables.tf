variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]+$", var.aws_region))
    error_message = "aws_region must be a valid AWS region format, e.g. us-east-1."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr must be a valid IPv4 CIDR block, e.g. 10.0.0.0/16."
  }
}

variable "availability_zones" {
  description = "Availability Zones to span (must belong to aws_region)"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]

  validation {
    condition     = length(var.availability_zones) >= 2
    error_message = "availability_zones must list at least two AZs; this stack is designed multi-AZ."
  }
}

variable "instance_type" {
  description = "EC2 instance type for the Auto Scaling group"
  type        = string
  default     = "t3.micro"

  validation {
    condition     = can(regex("^[a-z][a-z0-9]*\\.[a-z0-9]+$", var.instance_type))
    error_message = "instance_type must look like a real EC2 instance type, e.g. t3.micro."
  }
}

variable "asg_min_size" {
  description = "Minimum number of instances in the Auto Scaling group"
  type        = number
  default     = 1

  validation {
    condition     = var.asg_min_size >= 0
    error_message = "asg_min_size cannot be negative."
  }
}

variable "asg_max_size" {
  description = "Maximum number of instances in the Auto Scaling group"
  type        = number
  default     = 3

  validation {
    condition     = var.asg_max_size >= 1
    error_message = "asg_max_size must be at least 1."
  }
}

variable "asg_desired_capacity" {
  description = "Desired number of instances in the Auto Scaling group"
  type        = number
  default     = 2

  validation {
    condition     = var.asg_desired_capacity >= 0
    error_message = "asg_desired_capacity cannot be negative."
  }
}
