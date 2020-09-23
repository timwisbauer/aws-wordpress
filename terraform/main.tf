##################################################################
# Provider and backend configuration
##################################################################

provider "aws" {
  region = "us-east-1"
}

terraform {
  backend "s3" {
    bucket = "tfstate-timwisbauer-wordpress"
    key    = "default-infrastructure"
    region = "us-east-1"
  }
}

##################################################################
# Core networking configuration
##################################################################

data "aws_availability_zones" "available" {
  state = "available"
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> v2.0"

  name = var.project.name
  cidr = var.vpc_cidr_block

  azs             = data.aws_availability_zones.available.names
  private_subnets = slice(var.private_subnets, 0, var.project.private_subnets_per_vpc)
  public_subnets  = slice(var.public_subnets, 0, var.project.public_subnets_per_vpc)

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

  name           = var.project.name
  instance_count = var.project.instances_per_subnet * var.project.private_subnets_per_vpc

  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.project.instance_type
  monitoring             = true
  vpc_security_group_ids = [module.vpc.default_security_group_id]
  subnet_ids             = module.vpc.private_subnets[*]

  tags = {
    Terraform   = "true"
    Environment = "dev"
    Applicatipn = "wordpress"
  }
}

##################################################################
# ALB configuration
##################################################################
