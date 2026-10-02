terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Remote state (recommended for teams): copy backend.tf.example
  # to backend.tf, fill in your values, and run `terraform init`.
}
