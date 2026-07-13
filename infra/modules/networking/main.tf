resource "aws_eip" "nat" {
  count = 2

  domain = "vpc"
}

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "${var.project_name}_vpc"
  cidr = var.vpc_cidr

  azs             = var.az_range
  private_subnets = var.private_subnet_cidr
  public_subnets  = var.public_subnet_cidr
  create_igw      = true

  enable_nat_gateway = true
  enable_vpn_gateway = true

  single_nat_gateway  = false
  reuse_nat_ips       = true             # <= Skip creation of EIPs for the NAT Gateways
  external_nat_ip_ids = aws_eip.nat.*.id # <= IPs specified here as input to the module

  # Tags required by the AWS Load Balancer Controller to discover subnets.
  # Public subnets host internet-facing ALBs; private subnets host internal ones
  # and the EKS worker nodes.
  public_subnet_tags = {
    "kubernetes.io/role/elb"                        = "1"
    "kubernetes.io/cluster/${var.cluster_name}"     = "shared"
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"               = "1"
    "kubernetes.io/cluster/${var.cluster_name}"     = "shared"
  }

  tags = {
    Terraform   = "true"
    Environment = "dev"
  }
}

# Security group for interface VPC endpoints: allow HTTPS from within the VPC.
resource "aws_security_group" "vpc_endpoints" {
  name_prefix = "${var.project_name}-vpce-"
  description = "Allow HTTPS from the VPC to interface endpoints"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = {
    Terraform   = "true"
    Environment = "dev"
  }
}

# VPC endpoints keep ECR image pulls, S3 (model weights + layer blobs), and
# CloudWatch logs off the NAT gateways, cutting data-processing cost and
# keeping that traffic on the AWS backbone.
module "vpc_endpoints" {
  source  = "terraform-aws-modules/vpc/aws//modules/vpc-endpoints"
  version = "~> 5.0"

  vpc_id             = module.vpc.vpc_id
  security_group_ids = [aws_security_group.vpc_endpoints.id]

  endpoints = {
    s3 = {
      service         = "s3"
      service_type    = "Gateway"
      route_table_ids = module.vpc.private_route_table_ids
      tags            = { Name = "${var.project_name}-s3-vpce" }
    }
    ecr_api = {
      service             = "ecr.api"
      private_dns_enabled = true
      subnet_ids          = module.vpc.private_subnets
      tags                = { Name = "${var.project_name}-ecr-api-vpce" }
    }
    ecr_dkr = {
      service             = "ecr.dkr"
      private_dns_enabled = true
      subnet_ids          = module.vpc.private_subnets
      tags                = { Name = "${var.project_name}-ecr-dkr-vpce" }
    }
    logs = {
      service             = "logs"
      private_dns_enabled = true
      subnet_ids          = module.vpc.private_subnets
      tags                = { Name = "${var.project_name}-logs-vpce" }
    }
  }

  tags = {
    Terraform   = "true"
    Environment = "dev"
  }
}
