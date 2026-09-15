################################################################################
# Karpenter Configuration
################################################################################

# Karpenter Module
# Karpenter is a Kubernetes Node Autoscaler that enables just-in-time nodes for pods
module "karpenter" {
  source       = "terraform-aws-modules/eks/aws//modules/karpenter"    # Official community module - provisions everything Karpenter needs on the AWS side (IAM roles, instance profile, SQS interruption queue, EventBridge rules)
  version      = "21.3.2"                                              # Pinned module version, avoids surprise breaking changes on a future `terraform apply`
  cluster_name = module.eks.cluster_name                                # Tells the module which EKS cluster Karpenter will be managing nodes for
  iam_role_use_name_prefix = false                                      # Use the exact iam_role_name below instead of Terraform appending a random suffix (easier to find in the AWS console)

  iam_role_name = "KarpenterControllerRole-${module.eks.cluster_name}"  # Name of the IAM role the Karpenter *controller pod* assumes to call AWS APIs (RunInstances, DescribeInstanceTypes, etc.)

  # Enable IAM roles for service accounts using EKS Pod Identity
  create_pod_identity_association = true                                # Automatically creates the EKS Pod Identity Association that binds the karpenter-controller ServiceAccount to the IAM role above (no manual association needed)

  # Additional IAM policies for the nodes created by Karpenter
  # SSM allows for remote access to nodes for troubleshooting
  node_iam_role_additional_policies = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"  # Lets you SSM Session Manager into any node Karpenter launches, without SSH keys or a bastion host
  }
  node_iam_role_use_name_prefix = false                                  # Same idea as above, but for the *node's* role name (exact name, no random suffix)
  node_iam_role_name = "KarpenterNodeRole-${module.eks.cluster_name}"    # Name of the IAM role placed in the instance profile attached to every EC2 node Karpenter creates (this is the node's role, NOT the controller's)

  tags = local.tags                                                     # Common tags (Project/ManagedBy) applied to every resource this module creates
}

# Additional IAM policy for Karpenter controller
resource "aws_iam_policy" "karpenter_controller_additional" {
  name        = "KarpenterControllerAdditional-${module.eks.cluster_name}"
  description = "Additional permissions for Karpenter controller"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowInstanceProfilePermissions"   # Statement label - purely descriptive, shows up in IAM/CloudTrail for readability
        Effect = "Allow"
        Action = [
          "iam:AddRoleToInstanceProfile",             # Karpenter creates/manages instance profiles per EC2NodeClass and needs to attach the node role into them
          "iam:ListInstanceProfiles"                  # Lets Karpenter check which instance profiles already exist before deciding to create a new one
        ]
        Resource = "*"                                 # These are account-wide/list-style IAM actions - IAM doesn't support resource-level ARNs for them
      },
      {
        Sid    = "AllowAdditionalSQSActions"  # Needs SQS to catch AWS Spot 2-minute warnings so it can safely move pods before a server gets deleted.
        Effect = "Allow"
        Action = [
          "sqs:GetQueueUrl",                   # Resolve the interruption-queue URL from its name
          "sqs:GetQueueAttributes",            # Read queue metadata (used internally by the AWS SDK's polling loop)
          "sqs:DeleteMessage"                  # Remove an interruption notification once Karpenter has handled it (i.e. drained the affected node)
        ]
        Resource = module.karpenter.queue_arn  # Scoped only to this one interruption queue the module created - not "*"
      },
      {
        Sid      = "AllowPassRoleToKarpenterNodeRole"
        Effect   = "Allow"
        Action   = ["iam:PassRole"]                    # Required so the controller can hand off (pass) the node IAM role to EC2 when it launches a new instance
        Resource = module.karpenter.node_iam_role_arn  # Restricts PassRole to only this one role - the controller can't pass any other/more-privileged role (privilege-escalation guard)
      }
    ]
  })

  tags = local.tags
}

# Attach additional policy to Karpenter controller role
resource "aws_iam_role_policy_attachment" "karpenter_controller_additional" {
  role       = module.karpenter.iam_role_name                       # The controller role created by the module above...
  policy_arn = aws_iam_policy.karpenter_controller_additional.arn   # ...gets this extra policy attached to it
}
