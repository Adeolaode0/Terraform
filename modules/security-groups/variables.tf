variable "name_prefix" {
  description = "Naming prefix applied to all resources ({project}-{environment})"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC the security groups belong to"
  type        = string
}
