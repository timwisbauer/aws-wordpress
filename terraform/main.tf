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
  depends_on = [
    module.db
  ]

  name = var.project.name

  # Launch configuration
  lc_name = "${var.project.name}-lc"

  image_id             = data.aws_ami.amazon_linux.id
  instance_type        = var.project.instance_type
  security_groups      = [module.asg_security_group.this_security_group_id]
  iam_instance_profile = aws_iam_instance_profile.wordpress_secrets_profile.id

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

# AMI
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

# Userdata
locals {
  user_data = <<EOF
#!/bin/bash
yum update -y
cd /tmp
wget https://wordpress.org/latest.tar.gz
tar xvf latest.tar.gz
yum install -y httpd mariadb-server jq
amazon-linux-extras install -y php7.3
yum install -y php-pecl-mcrypt php-pecl-imagick php-mbstring
systemctl enable mariadb
systemctl start mariadb
systemctl enable httpd
systemctl start httpd
rsync -r /tmp/wordpress/. /var/www/html
aws secretsmanager get-secret-value --secret-id wordpress-rds-secrets --query SecretString --version-stage AWSCURRENT --region us-east-1 --output text | jq -r 'to_entries|map("\(.key)=\(.value|tostring)")|.[]' > /var/www/.env
curl -sS https://getcomposer.org/installer | sudo php
mv composer.phar /usr/local/bin/composer
ln -s /usr/local/bin/composer /usr/bin/composer
cd /var/www/
wget https://raw.githubusercontent.com/rayheffer/wp-secrets/master/wp-config.php
wget https://raw.githubusercontent.com/rayheffer/wp-secrets/master/composer.json
sudo composer install
chown -R apache:apache /var/www/
EOF
}

# Security group allowing ALB to EC2 instances.
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
  egress_rules        = ["all-all"]
}

# IAM role, policy, and instance profile for accessing secrets from AWS Secrets Manager.
resource "aws_iam_role" "wordpress_iam_role" {
  name = "wordpress_iam_role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF

  tags = {
    application = "wordpress"
  }
}

resource "aws_iam_role_policy" "wordpress_secrets_policy" {
  name = "wordpress_secrets_policy"
  role = aws_iam_role.wordpress_iam_role.id

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "secretsmanager:GetSecretValue"
      ],
      "Effect": "Allow",
      "Resource": "${data.aws_secretsmanager_secret_version.rds_creds.arn}"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "wordpress_ssm_policy" {
  name = "wordpress_ssm_policy"
  role = aws_iam_role.wordpress_iam_role.id

  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ssm:DescribeAssociation",
                "ssm:GetDeployablePatchSnapshotForInstance",
                "ssm:GetDocument",
                "ssm:DescribeDocument",
                "ssm:GetManifest",
                "ssm:GetParameter",
                "ssm:GetParameters",
                "ssm:ListAssociations",
                "ssm:ListInstanceAssociations",
                "ssm:PutInventory",
                "ssm:PutComplianceItems",
                "ssm:PutConfigurePackageResult",
                "ssm:UpdateAssociationStatus",
                "ssm:UpdateInstanceAssociationStatus",
                "ssm:UpdateInstanceInformation"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "ssmmessages:CreateControlChannel",
                "ssmmessages:CreateDataChannel",
                "ssmmessages:OpenControlChannel",
                "ssmmessages:OpenDataChannel"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "ec2messages:AcknowledgeMessage",
                "ec2messages:DeleteMessage",
                "ec2messages:FailMessage",
                "ec2messages:GetEndpoint",
                "ec2messages:GetMessages",
                "ec2messages:SendReply"
            ],
            "Resource": "*"
        }
    ]
}
EOF
}

resource "aws_iam_instance_profile" "wordpress_secrets_profile" {
  name = "wordpress_secrets_profile"
  role = aws_iam_role.wordpress_iam_role.id
}

##################################################################
# RDS configuration
##################################################################

module "db" {
  source  = "terraform-aws-modules/rds/aws"
  version = "~> 2.0"

  identifier = "wordpress-db"

  engine            = "mysql"
  engine_version    = "5.7.26"
  instance_class    = "db.t3.medium"
  allocated_storage = 5

  name     = local.db_creds.dbname
  username = local.db_creds.username
  password = local.db_creds.password
  port     = "3306"

  vpc_security_group_ids = [module.rds_security_group.this_security_group_id]

  backup_retention_period = 0
  maintenance_window      = "Mon:00:00-Mon:03:00"
  backup_window           = "03:00-06:00"

  # # Enhanced Monitoring - see example for details on how to create the role
  # # by yourself, in case you don't want to create it automatically
  # monitoring_interval    = "30"
  # monitoring_role_name   = "MyRDSMonitoringRole"
  # create_monitoring_role = true

  tags = {
    application = "wordpress"
  }

  # DB subnet group
  subnet_ids = module.vpc.private_subnets[*]

  # DB parameter group
  family = "mysql5.7"

  # DB option group
  major_engine_version = "5.7"

  # # Snapshot name upon DB deletion
  # final_snapshot_identifier = "wordpressdb"

  # Database Deletion Protection
  deletion_protection = false

  parameters = [
    {
      name  = "character_set_client"
      value = "utf8"
    },
    {
      name  = "character_set_server"
      value = "utf8"
    }
  ]

  options = [
    {
      option_name = "MARIADB_AUDIT_PLUGIN"

      option_settings = [
        {
          name  = "SERVER_AUDIT_EVENTS"
          value = "CONNECT"
        },
        {
          name  = "SERVER_AUDIT_FILE_ROTATIONS"
          value = "37"
        },
      ]
    },
  ]
}

# Security group allowing EC2 instances to connect.
module "rds_security_group" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 3.0"

  name        = "rds-sg-${var.project.name}"
  description = "Security group for RDS"
  vpc_id      = module.vpc.vpc_id

  ingress_with_source_security_group_id = [
    {
      rule                     = "mysql-tcp"
      source_security_group_id = module.asg_security_group.this_security_group_id
    }
  ]
}

# RDS credentials out of Secrets Manager
data "aws_secretsmanager_secret_version" "rds_creds" {
  secret_id = "wordpress-rds-secrets"
}

locals {
  db_creds = jsondecode(
    data.aws_secretsmanager_secret_version.rds_creds.secret_string
  )
}
