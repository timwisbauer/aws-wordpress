provider "aws" {
  region  = "us-east-1"
}

terraform {
  backend "s3" {
    bucket = "tfstate-timwisbauer-tf-ansible-wordpress"
    key    = "default-infrastructure"
    region = "us-east-1"
  }
}