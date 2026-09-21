terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Remote state (recommended for teams). Uncomment and fill in to use:
  # backend "s3" {
  #   bucket         = "REPLACE_ME-terraform-state"
  #   key            = "terraform-aws-infrastructure/dev.tfstate"
  #   region         = "us-east-1"
  #   dynamodb_table = "terraform-state-locks"
  #   encrypt        = true
  # }
}
