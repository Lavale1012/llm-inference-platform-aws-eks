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
