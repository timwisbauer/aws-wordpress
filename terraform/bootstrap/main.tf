# Bootstraps S3 bucket.  Necessary because I'm typically developing in a short-lived demo AWS account.
provider "aws" {
  region = "us-east-1"
}

resource "aws_s3_bucket" "terraform_state" {
  bucket = "tfstate-timwisbauer-tf-ansible-wordpress"

  versioning {
    enabled = false
  }

  lifecycle {
    prevent_destroy = false
  }
}
