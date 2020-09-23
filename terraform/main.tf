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
# ALB configuration
##################################################################



module "alb" {
  source  = "terraform-aws-modules/alb/aws"
  version = "~> 5.0"

  name = var.project.name

  load_balancer_type = "application"

  vpc_id          = module.vpc.vpc_id
  subnets         = module.vpc.public_subnets[*]
  security_groups = [module.alb_security_group.this_security_group_id]

  target_groups = [
    {
      name_prefix      = "wp-"
      backend_protocol = "HTTP"
      backend_port     = 80
      health_check = {
        path = "/phpinfo.php"
      }
    }
  ]
  http_tcp_listeners = [
    {
      port               = 80
      protocol           = "HTTP"
      target_group_index = 0
    }
  ]

  tags = {
    Application = "wordpress"
  }
}

module "alb_security_group" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 3.0"

  name        = "alb-sg-${var.project.name}"
  description = "Security group for ALB"
  vpc_id      = module.vpc.vpc_id

  ingress_cidr_blocks = ["0.0.0.0/0"]
  ingress_rules       = ["http-80-tcp", "all-icmp"]
  egress_rules        = ["all-all"]
}

##################################################################
# ASG configuration
##################################################################

module "asg" {
  source  = "terraform-aws-modules/autoscaling/aws"
  version = "~> 3.0"

  name = var.project.name

  # Launch configuration
  lc_name = "${var.project.name}-lc"

  image_id        = data.aws_ami.amazon_linux.id
  instance_type   = var.project.instance_type
  security_groups = [module.alb_security_group.this_security_group_id]

  ebs_block_device = [
    {
      device_name           = "/dev/xvdz"
      volume_type           = "gp2"
      volume_size           = "8"
      delete_on_termination = true
    },
  ]

  root_block_device = [
    {
      volume_size = "8"
      volume_type = "gp2"
    },
  ]

  # Auto scaling group
  asg_name                  = var.project.name
  vpc_zone_identifier       = module.vpc.private_subnets[*]
  health_check_type         = "EC2"
  min_size                  = 1
  max_size                  = 9
  desired_capacity          = 3
  wait_for_capacity_timeout = 0
  target_group_arns         = module.alb.target_group_arns
  user_data_base64          = base64encode(local.user_data)


  tags_as_map = {
    application = "wordpress"

  }
}

data "aws_ami" "amazon_linux" {
  most_recent = true

  owners = ["amazon"]

  filter {
    name = "name"

    values = [
      "amzn2-ami-hvm-*-x86_64-gp2",
    ]
  }

  filter {
    name = "owner-alias"

    values = [
      "amazon",
    ]
  }
}

locals {
  user_data = <<EOF
#!/bin/bash
yum update -y
amazon-linux-extras install -y lamp-mariadb10.2-php7.2 php7.2
yum install -y httpd mariadb-server
systemctl start httpd
systemctl enable httpd
usermod -a -G apache ec2-user
chown -R ec2-user:apache /var/www
chmod 2775 /var/www
find /var/www -type d -exec chmod 2775 {} \;
find /var/www -type f -exec chmod 0664 {} \;
echo "<?php phpinfo(); ?>" > /var/www/html/phpinfo.php
EOF
}

module "asg_security_group" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 3.0"

  name        = "asg-sg-${var.project.name}"
  description = "Security group for ASG"
  vpc_id      = module.vpc.vpc_id

  ingress_with_source_security_group_id = [
    {
      rule                     = "http-80-tcp"
      source_security_group_id = module.alb_security_group.this_security_group_id
    }
  ]
}
