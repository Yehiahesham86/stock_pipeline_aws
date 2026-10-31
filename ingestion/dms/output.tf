
output "replication_instance_arn" {
  description = "ARN of the DMS replication instance"
  value       = aws_dms_replication_instance.stock.replication_instance_arn
}

output "replication_instance_private_ips" {
  description = "Private IP addresses of the DMS instance"
  value       = aws_dms_replication_instance.stock.replication_instance_private_ips
}

output "dms_security_group_id" {
  description = "Security group attached to DMS"
  value       = aws_security_group.dms.id
}

output "dms_subnet_group_id" {
  description = "DMS replication subnet group ID"
  value       = aws_dms_replication_subnet_group.stock.id
}
