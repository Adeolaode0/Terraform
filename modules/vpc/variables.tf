variable "name_prefix" {
  description = "Naming prefix applied to all resources ({project}-{environment})"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
}

variable "availability_zones" {
  description = "Availability Zones to span"
  type        = list(string)
}

variable "enable_nat_gateway" {
  description = "Create a NAT gateway so private subnets get outbound internet"
  type        = bool
  default     = true
}
