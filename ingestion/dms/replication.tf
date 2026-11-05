
resource "aws_dms_replication_subnet_group" "stock" {
  replication_subnet_group_id          = "stock-pipeline-dms-subnets"
  replication_subnet_group_description = "Subnets for stock pipeline DMS"

  subnet_ids = data.terraform_remote_state.vpc.outputs.public_subnet_ids

  tags = {
    Name    = "stock-pipeline-dms-subnets"
    Project = "StockDataPipeline"
  }
}

resource "aws_dms_replication_instance" "stock" {
  replication_instance_id    = "stock-pipeline-dms"
  replication_instance_class = var.replication_instance_class
  allocated_storage          = var.allocated_storage

  publicly_accessible = true

  vpc_security_group_ids = [
    aws_security_group.dms.id
  ]

  replication_subnet_group_id = aws_dms_replication_subnet_group.stock.id

  apply_immediately = true

  tags = {
    Name    = "stock-pipeline-dms"
    Project = "StockDataPipeline"
  }
}

