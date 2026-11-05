
resource "aws_security_group" "dms" {
  name        = "stock-pipeline-dms-sg"
  description = "Network access for stock pipeline DMS"
  vpc_id      = data.terraform_remote_state.vpc.outputs.vpc_id

  egress {
    description = "Outbound connectivity for DMS"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "stock-pipeline-dms-sg"
    Project = "StockDataPipeline"
  }
}
