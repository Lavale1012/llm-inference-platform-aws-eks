data "aws_caller_identity" "current" {}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name               = var.cluster_name
  kubernetes_version = var.kubernetes_version


  addons = {
    coredns = {}
    eks-pod-identity-agent = {
      before_compute = true
    }
    kube-proxy = {}
    vpc-cni = {
      before_compute = true
    }
    # Persistent volumes for model weights / caches (PVCs bind via this driver).
    aws-ebs-csi-driver = {}
    # Feeds the ContainerInsights metric namespace the node CPU/memory alarms read.
    amazon-cloudwatch-observability = {}
  }

  # Optional
  endpoint_public_access = true

  # Optional: Adds the current caller identity as an administrator via cluster access entry
  enable_cluster_creator_admin_permissions = true

  vpc_id                   = var.vpc_id
  subnet_ids               = var.subnet_ids
  control_plane_subnet_ids = var.control_plane_subnet_ids

  # EKS Managed Node Group(s)
  eks_managed_node_groups = {
    # General-purpose (CPU) nodes: run system pods, the LB controller,
    # CoreDNS, CSI/observability agents, etc.
    system = {
      # Starting on 1.30, AL2023 is the default AMI type for EKS managed node groups
      ami_type       = var.ami
      instance_types = var.instance_types

      min_size     = var.min_size
      max_size     = var.max_size
      desired_size = var.desired_size
    }

    # GPU nodes for LLM inference. Tainted so only GPU workloads (pods that
    # tolerate nvidia.com/gpu) schedule here, keeping expensive GPUs free of
    # system pods. Requires the NVIDIA device plugin DaemonSet in-cluster to
    # advertise the nvidia.com/gpu resource.
    gpu = {
      ami_type       = var.gpu_ami_type
      instance_types = var.gpu_instance_types

      min_size     = var.gpu_min_size
      max_size     = var.gpu_max_size
      desired_size = var.gpu_desired_size

      labels = {
        "workload-type" = "gpu-inference"
      }

      taints = {
        gpu = {
          key    = "nvidia.com/gpu"
          value  = "true"
          effect = "NO_SCHEDULE"
        }
      }
    }
  }

  tags = {
    Environment = "dev"
    Terraform   = "true"
  }
}

# IAM role for the AWS Load Balancer Controller, granted to its service
# account via EKS Pod Identity. The submodule attaches the maintained
# LB Controller IAM policy so we don't have to inline it.
module "aws_lb_controller_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 1.0"

  name = "${var.cluster_name}-aws-lbc"

  attach_aws_lb_controller_policy = true

  # Bind the role to the controller's service account in kube-system.
  associations = {
    this = {
      cluster_name    = module.eks.cluster_name
      namespace       = "kube-system"
      service_account = "aws-load-balancer-controller"
    }
  }

  tags = {
    Environment = "dev"
    Terraform   = "true"
  }
}

# Install the AWS Load Balancer Controller via Helm. It watches Ingress /
# Service resources and provisions ALBs/NLBs, registering pods as targets.
# Permissions come from the Pod Identity association above, so the chart
# creates a plain service account with no IAM annotation.
resource "helm_release" "aws_lb_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  version    = var.aws_lb_controller_chart_version

  set = [
    {
      name  = "clusterName"
      value = module.eks.cluster_name
    },
    {
      name  = "serviceAccount.create"
      value = "true"
    },
    {
      name  = "serviceAccount.name"
      value = "aws-load-balancer-controller"
    },
    {
      name  = "region"
      value = var.aws_region
    },
    {
      name  = "vpcId"
      value = var.vpc_id
    },
  ]

  # The IAM role/association must exist before the controller starts, and the
  # cluster must be reachable (node group ready to schedule the pod).
  depends_on = [
    module.aws_lb_controller_pod_identity,
    module.eks,
  ]
}

# NVIDIA device plugin: a DaemonSet that advertises the nvidia.com/gpu resource
# so Kubernetes can schedule GPU workloads. Without it, GPU nodes exist but pods
# requesting nvidia.com/gpu stay Pending. It must tolerate the GPU taint and
# only run on GPU nodes (nodeSelector on the label set in the gpu node group).
resource "helm_release" "nvidia_device_plugin" {
  name             = "nvidia-device-plugin"
  repository       = "https://nvidia.github.io/k8s-device-plugin"
  chart            = "nvidia-device-plugin"
  namespace        = "nvidia-device-plugin"
  create_namespace = true
  version          = var.nvidia_device_plugin_chart_version

  set = [
    {
      name  = "tolerations[0].key"
      value = "nvidia.com/gpu"
    },
    {
      name  = "tolerations[0].operator"
      value = "Equal"
    },
    {
      name  = "tolerations[0].value"
      value = "true"
    },
    {
      name  = "tolerations[0].effect"
      value = "NoSchedule"
    },
    {
      name  = "nodeSelector.workload-type"
      value = "gpu-inference"
    },
  ]

  depends_on = [module.eks]
}

# Private ECR repository for application images. EKS nodes can pull from it
# automatically (the managed node group IAM role has
# AmazonEC2ContainerRegistryReadOnly). Push access is granted to the current
# Terraform caller plus any CI role ARNs supplied via var.ecr_push_role_arns.
module "ecr" {
  source  = "terraform-aws-modules/ecr/aws"
  version = "~> 3.0"

  repository_name = "${var.repository_name}-ecr"

  # Image hardening: immutable tags prevent overwriting a pushed tag,
  # scan-on-push surfaces CVEs when an image is pushed.
  repository_image_tag_mutability = var.image_tag_mutability
  repository_image_scan_on_push   = var.image_scan_on_push

  repository_read_write_access_arns = concat(
    [data.aws_caller_identity.current.arn],
    var.ecr_push_role_arns,
  )

  repository_lifecycle_policy = jsonencode({
    rules = [
      {
        rulePriority = 1,
        description  = "Keep last 30 tagged images",
        selection = {
          tagStatus     = "tagged",
          tagPrefixList = ["v"],
          countType     = "imageCountMoreThan",
          countNumber   = 30
        },
        action = {
          type = "expire"
        }
      }
    ]
  })

  tags = {
    Terraform   = "true"
    Environment = "dev"
  }
}
