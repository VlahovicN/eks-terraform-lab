terraform {
    required_version = ">=1.5.0"

    required_providers {
      aws = {
        source = "hashicorp/aws"
        version = "~> 6.0"
      }
      kubernetes = {
        source = "hashicorp/kubernetes"
        version = "~> 2.31.0"
      }
      helm = {
        source  = "hashicorp/helm"
        version = "~> 3.0.2"
      }
      kubectl = {
        source  = "gavinbunney/kubectl"
        version = "1.14.0"
      }
    }

    # S3 Backedn Config
    backend "s3" {
        bucket         = "nikolav-tf-state"                   # Name of the S3 Bucket
        key            = "eks-infra/terraform.tfstate"       # Path inside the bucket
        region         = "us-east-1"                         # The region
        dynamodb_table = "terraform-state-locking"           # Name of the dynamodb table
        encrypt        = true                                # Encrypt the file
    }
}

provider "aws" {
  region = "us-east-1"
}