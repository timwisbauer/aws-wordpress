# Objective

Demo deployment showing usage of Terraform and Ansible to deploy Wordpress in AWS.

# Overview

Two tier deployment to separate app/db
RDS for database
ALB in front of Wordpress app servers

## Usage

Add Github secrets with sandbox credentials.
    AWS_ACCESS_KEY_ID
    AWS_SECRET_ACCESS_KEY

Trigger CI run manually or via pull request.