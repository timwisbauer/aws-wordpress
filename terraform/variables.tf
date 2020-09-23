variable project {
  description = "Map of configuration values for networking to support EC2 instances."
  type        = map
  default = {
    name                    = "wordpress"
    public_subnets_per_vpc  = 3,
    private_subnets_per_vpc = 3,
    instances_per_subnet    = 1,
    instance_type           = "t2.micro",
  }
}

variable vpc_cidr_block {
  description = "VPC CIDR"
  type        = string
  default     = "10.0.0.0/16"
}

variable public_subnets {
  description = "Available public subnets."
  type        = list(string)
  default = [
    "10.0.101.0/24",
    "10.0.102.0/24",
    "10.0.103.0/24",
    "10.0.104.0/24",
    "10.0.105.0/24",
    "10.0.106.0/24"
  ]
}

variable private_subnets {
  description = "Available private subnets."
  type        = list(string)
  default = [
    "10.0.1.0/24",
    "10.0.2.0/24",
    "10.0.3.0/24",
    "10.0.4.0/24",
    "10.0.5.0/24",
    "10.0.6.0/24"
  ]
}
