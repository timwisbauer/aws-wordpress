output "db_endpoint" {
    description = "RDS endpoint"
    value = module.db.this_db_instance_endpoint
}

output "alb" {
    description = "ALB endpoint"
    value = module.alb.this_lb_dns_name
}