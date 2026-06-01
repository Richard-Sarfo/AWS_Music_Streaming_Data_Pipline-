terraform {
  required_version = ">= 1.9"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.70"
    }
  }

  backend "s3" {
    bucket         = "p1-tfstate-dev-982081084448"
    key            = "p1/streaming-pipeline.tfstate"
    region         = "us-east-1"
    dynamodb_table = "p1-tflock-dev"
    encrypt        = true
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = local.tags
  }
}
