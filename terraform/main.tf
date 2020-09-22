##################################################################
# Provider and backend configuration
##################################################################

provider "aws" {
  region = "us-east-1"
}

terraform {
  backend "s3" {
    bucket = "tfstate-timwisbauer-tf-ansible-wordpress"
    key    = "default-infrastructure"
    region = "us-east-1"
  }
}

##################################################################
# Core networking configuration
##################################################################

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> v2.0"

  name = "tf-ansible-wordpress"
  cidr = "10.0.0.0/16"

  azs             = ["us-east-1a", "us-east-1b", "us-east-1c"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  enable_nat_gateway = true

  tags = {
    Terraform   = "true"
    Environment = "dev"
    Application = "wordpress"
  }
}

##################################################################
# EC2 instances
##################################################################

data "aws_ami" "amazon_linux" {
  most_recent = true

  owners = ["amazon"]

  filter {
    name = "name"

    values = [
      "amzn-ami-hvm-*-x86_64-gp2",
    ]
  }

  filter {
    name = "owner-alias"

    values = [
      "amazon",
    ]
  }
}

module "wordpress_instances" {
  source  = "terraform-aws-modules/ec2-instance/aws"
  version = "~> 2.0"

  for_each = toset(module.vpc.private_subnets)

  name           = "wordpress"
  instance_count = 1

  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t2.micro"
  monitoring             = true
  vpc_security_group_ids = [module.vpc.default_security_group_id]
  subnet_id              = each.value

  tags = {
    Terraform   = "true"
    Environment = "dev"
    Applicatipn = "wordpress"
  }
}

##################################################################
# ALB configuration
##################################################################
