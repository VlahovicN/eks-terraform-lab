module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0.8"

  name               = local.cluster_name
  kubernetes_version = var.kubernetes_version

  addons = {
    coredns = {
      before_compute              = true
      resolve_conflicts_on_update = "OVERWRITE"
    }
    eks-pod-identity-agent = {
      before_compute              = true
      resolve_conflicts_on_update = "OVERWRITE"
    }
    kube-proxy = {
      before_compute              = true
      resolve_conflicts_on_update = "OVERWRITE"
    }
    vpc-cni = {
      before_compute              = true
      resolve_conflicts_on_create = "OVERWRITE"
      resolve_conflicts_on_update = "OVERWRITE"
  }
}
  # Optional
  endpoint_public_access = true  # Enables public access to the EKS API endpoint

  authentication_mode = "API"


  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = module.vpc.public_subnets
  control_plane_subnet_ids = module.vpc.public_subnets

  # EKS Managed Node Group(s)
  eks_managed_node_groups = {
    critical-components = {
      # Starting on 1.30, AL2023 is the default AMI type for EKS managed node groups
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = ["t3.medium"]

      min_size     = 2
      max_size     = 3
      desired_size = 2

      associate_public_ip_address = true # Since nodes will be in public subnets, they will need a public ip address

      taints = {
        components = {
            key    = "CriticalAddonsOnly"
            value  = "true"
            effect = "NO_SCHEDULE"
        }
      }

      monitoring = true
      metadata_options = {
        http_put_response_hop_limit = 2
      }

    }
  }

  tags = local.tags


  node_security_group_additional_rules = {
# Rule: ingress_self_all (Node-to-Node Intra-Cluster Communication)
    # -----------------------------------------------------------------------------------------
    # WHAT: Allows all inbound traffic (all ports and protocols) between the worker nodes themselves.
    # WHY: In Kubernetes, pods belonging to the same application stack (e.g., frontend and backend) 
    # are often scheduled on different EC2 instances and must communicate freely over the network. 
    # Without this rule, AWS would block node-to-node traffic, breaking microservice communication.
    ingress_self_all = {
      description = "Node to node all ports/protocols"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "ingress"
      self        = true
    }
# Rule: egress_all (Outbound Internet and Network Access)
    # -----------------------------------------------------------------------------------------
    # WHAT: Allows unrestricted outbound traffic (all ports and protocols) from nodes to any destination.
    # WHY: Worker nodes must access the public internet and AWS endpoints to pull container images 
    # from registries (like ECR or Docker Hub), download system updates, fetch network
    # drivers, and ship logs or metrics to monitoring services like CloudWatch.
    egress_all = {
      description      = "Node all egress"
      protocol         = "-1"
      from_port        = 0
      to_port          = 0
      type             = "egress"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = ["::/0"]
    }
# Rule: ingress_cluster_to_node_all_traffic (Control Plane to Worker Node Connection)
    # -----------------------------------------------------------------------------------------
    # WHAT: Opens a direct connection from the EKS Control Plane to the worker nodes.
    # WHY: The EKS Control Plane needs to send commands and talk to the nodes constantly. 
    # Without this rule, basic terminal commands like checking container logs ('kubectl logs') 
    # or jumping inside a container ('kubectl exec') would time out and fail completely because 
    # AWS would block the connection from the master cluster to the machines.
    ingress_cluster_to_node_all_traffic = {
      description                   = "Cluster API to Nodegroup all traffic"
      protocol                      = "-1"
      from_port                     = 0
      to_port                       = 0
      type                          = "ingress"
      source_cluster_security_group = true
    }

  }

    node_security_group_tags = {
        "karpenter.sh/discovery" = local.cluster_name
    }

}


################################################################
# EKS Access Entry: Setting my own account as cluster admin    #
################################################################

resource "aws_eks_access_entry" "root_admin" {
  cluster_name      = module.eks.cluster_name
  principal_arn     = data.aws_caller_identity.current.arn
  type              = "STANDARD"
  
  depends_on = [module.eks]
}

resource "aws_eks_access_policy_association" "root_admin_association" {
  cluster_name  = module.eks.cluster_name
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  principal_arn = data.aws_caller_identity.current.arn

  access_scope {
    type = "cluster"
  }
  depends_on = [aws_eks_access_entry.root_admin]
}



##########################################################################################
# Kubernetes & Helm providers configuration
##########################################################################################
# Provider responsible  for managing the EKS cluster resources
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  # Required for terrafrom to be able to see resources in the EKS Cluster
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
    command     = "aws"
  }
}

# Provider responsible  for managining Helm releases, repositories & charts
provider "helm" {
  kubernetes = {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    # Required for terrafrom to be able to see resources in the EKS Cluster
    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
      command     = "aws"
    }
  }
}



###########################################################
# KEDA                                                    #
###########################################################
resource "helm_release" "keda" {
  name       = "keda"
  namespace  = "keda"
  repository = "https://kedacore.github.io/charts"
  chart      = "keda"
  version    = "2.19.0"

  create_namespace = true

  values = [
    yamlencode({
      metricsServer = {
        enabled = true
      }
      tolerations = [
        {
          key      = "CriticalAddonsOnly"
          operator = "Exists"
          effect   = "NoSchedule"
        }
      ]
    })
  ]

  depends_on = [module.eks]
}


##########################################################################################
# KEDA Pod Identity Setup (With custom SQS & CloudWatch permissions)
##########################################################################################

resource "aws_iam_role" "keda_operator_role" {
  name = "${local.cluster_name}-keda-operator-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "pods.eks.amazonaws.com"
        }
        Action = [
          "sts:AssumeRole",
          "sts:TagSession"
        ]
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })

  tags = local.tags
}


resource "aws_iam_policy" "keda_operator_policy" {
  name        = "${local.cluster_name}-keda-operator-policy"
  description = "Custom permissions for KEDA Operator to manage SQS and read CloudWatch metrics"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "sqs:GetQueueAttributes",
          "sqs:GetQueueUrl",
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:ChangeMessageVisibility"
        ],
        Effect   = "Allow",
        Resource = "*"  # Needs SQS only if using the SQS scaler, to check the number of messages in a queue so it knows how many application pods to scale up or down.
      },
      {
        Action = [
          "cloudwatch:GetMetricData",
          "cloudwatch:ListMetrics",
          "cloudwatch:GetMetricStatistics"
        ],
        Effect   = "Allow",
        Resource = "*"
      }
    ]
  })

  tags = local.tags
}


resource "aws_iam_role_policy_attachment" "keda_operator_attach" {
  role       = aws_iam_role.keda_operator_role.name
  policy_arn = aws_iam_policy.keda_operator_policy.arn
}


resource "aws_eks_pod_identity_association" "keda_operator" {
  cluster_name    = module.eks.cluster_name
  namespace       = "keda"
  service_account = "keda-operator"
  role_arn        = aws_iam_role.keda_operator_role.arn

  depends_on = [helm_release.keda]
}


#######################################################
# EKS Pod Identity Association: External Secrets      #
#######################################################

resource "aws_eks_pod_identity_association" "external_secrets" {
  cluster_name    = module.eks.cluster_name
  namespace       = "external-secrets"
  service_account = "external-secrets"
  role_arn        = aws_iam_role.eso_role.arn
  depends_on      = [module.eks]
}