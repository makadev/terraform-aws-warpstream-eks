variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "kubernetes_version" {
  type = string
  default = "1.34"
}

locals {
  name = "ex-warpstream-eks-${basename(path.cwd)}"
  version = var.kubernetes_version
  region = var.aws_region
}

variable "warpstream_virtual_cluster_id" {
  description = "The warpstream virtual cluster id"
  type        = string
}

variable "warpstream_agent_key" {
  description = "The agent key for the warpstream cluster"
  type        = string
  sensitive   = true
}

provider "aws" {
  region = local.region
}

# Creating a VPC for this example, you can bring your own VPC
# if you already have one and don't need to use the one created here.
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.21.0"

  name = local.name

  cidr = "10.0.0.0/16"

  azs             = ["${local.region}a", "${local.region}b", "${local.region}c"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  enable_nat_gateway     = true
  single_nat_gateway     = false
  one_nat_gateway_per_az = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }

  # Default security group in the VPC to allow all egressing.
  default_security_group_egress = [
    {
      description = "Allow all egress"
      cidr_blocks = "0.0.0.0/0"
    },
  ]
}

# It is highly recommended to create a S3 Gateway endpoint in your VPC.
# This is to prevent S3 network traffic from egressing over your NAT Gateway and increasing costs.
module "endpoints" {
  source  = "terraform-aws-modules/vpc/aws//modules/vpc-endpoints"
  version = "5.21.0"

  vpc_id = module.vpc.vpc_id

  create_security_group      = true
  security_group_name_prefix = "${local.name}-vpc-endpoints-"
  security_group_description = "VPC endpoint security group"

  # Security group for the endpoints.
  # We are allowing everything in the VPC to connect to the S3 endpoint.
  security_group_rules = {
    ingress_https = {
      description = "HTTPS from VPC"
      cidr_blocks = [module.vpc.vpc_cidr_block]
    }
  }

  endpoints = {
    s3 = {
      service         = "s3"
      service_type    = "Gateway"
      route_table_ids = module.vpc.private_route_table_ids
      tags            = { Name = local.name }
    },
    # If you need a special low-latency S3 endpoint (S3 Express),
    # create it outside this generic example or add the correct
    # provider/service name here. Default public S3 gateway endpoint
    # is provided above.
  }
}

# Creating an EKS cluster for this example, you can bring your own cluster
# if you already have one and don't need to use the one created here.
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.37.1"

  cluster_name                   = local.name
  cluster_version                = local.version
  cluster_endpoint_public_access = true

  enable_cluster_creator_admin_permissions = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  eks_managed_node_group_defaults = {
    instance_types = ["m7a.xlarge"]
  }

  eks_managed_node_groups = {
    warpstream_agent_nodes = {
      min_size     = 3
      max_size     = 6
      desired_size = 3

      // m7(a/i).2xlarge = 8 vCPU + 32GB RAM
      instance_types = ["m7a.2xlarge", "m7i.2xlarge"]
      capacity_type  = "ON_DEMAND"
    }
  }
}

provider "helm" {
  kubernetes = {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      args        = ["eks", "get-token", "--cluster-name", local.name]
      command     = "aws"
    }
  }

}

module "warpstream" {
  source = "../.."

  resource_prefix      = local.name
  control_plane_region = local.region
  kubernetes_namespace = "default"

  # Zone count must match the number of zones in the EKS cluster so the
  # WarpStream pods get evenly distributed across all zones
  zone_count = length(module.vpc.private_subnets)

  eks_oidc_provider_arn = module.eks.oidc_provider_arn
  eks_oidc_issuer_url   = module.eks.cluster_oidc_issuer_url

  warpstream_virtual_cluster_id = var.warpstream_virtual_cluster_id
  warpstream_agent_key          = var.warpstream_agent_key

  bucket_names = [aws_s3_bucket.bucket.bucket]
}
