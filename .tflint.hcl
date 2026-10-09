config {
  format = "compact"
  module = true
}

plugin "aws" {
  enabled = true
  version = "0.32.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}

# Discouraged / invalid resource configurations for the modules we use
rule "aws_instance_invalid_type" {
  enabled = true
}

rule "aws_instance_invalid_iam_profile" {
  enabled = true
}

rule "aws_alb_invalid_security_group" {
  enabled = true
}

rule "aws_lb_target_group_invalid_protocol" {
  enabled = true
}

rule "aws_db_instance_invalid_type" {
  enabled = true
}

rule "aws_route_invalid_gateway" {
  enabled = true
}

rule "aws_subnet_invalid_availability_zone" {
  enabled = true
}

# Deprecated syntax catches dead code and future breakage early
rule "terraform_deprecated_syntax" {
  enabled = true
}

rule "terraform_unused_declarations" {
  enabled = true
}

rule "terraform_comment_syntax" {
  enabled = true
}
