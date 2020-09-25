# Objective

Demo deployment showing usage of Terraform to deploy Wordpress in AWS.

# Overview

Autoscaling groups of EC2 instances for compute
RDS for database
ALB in front of Wordpress app servers
AWS Secrets Manager holding DB connection information and Wordpress keys.

## Usage

Add Github secrets with sandbox credentials.  
    
- AWS_ACCESS_KEY_ID  
- AWS_SECRET_ACCESS_KEY  

Trigger CI run manually or via pull request.

## TODO/Improvements
- Automate AWS Secrets Manager adding secrets.  Pre-determined (like a password) or dynamic (like a RDS connection string).
- TLS
- Build AMI with Packer with hardened and preconfigured app servers.
- Move RDS instances to seperate subnets?
- Is mariadb needed on the app servers?