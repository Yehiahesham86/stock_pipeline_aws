terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

# Define variables for the S3 bucket name and AWS region
provider "aws" {
  region = var.aws_region
}

resource "aws_vpc" "stock_pipeline" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name    = "stock-pipeline-vpc"
    Project = "StockDataPipeline"
  }
}

resource "aws_internet_gateway" "stock_pipeline" {
  vpc_id = aws_vpc.stock_pipeline.id

  tags = {
    Name = "stock-pipeline-igw"
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.stock_pipeline.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "stock-pipeline-public-a"
  }
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.stock_pipeline.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true

  tags = {
    Name = "stock-pipeline-public-b"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.stock_pipeline.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.stock_pipeline.id
  }

  tags = {
    Name = "stock-pipeline-public-rt"
  }
}

resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}
