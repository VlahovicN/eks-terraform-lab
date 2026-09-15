################################################################################
# App2 - SQS Queue & Pod Identity (Consumer-only)
################################################################################

resource "aws_sqs_queue" "app2_queue" {
  name = "${local.cluster_name}-app2-queue"

  tags = local.tags
}

resource "aws_iam_role" "app2_role" {
  name = "${local.cluster_name}-app2-role"

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
      }
    ]
  })

  tags = local.tags
}

resource "aws_iam_policy" "app2_policy" {
  name        = "${local.cluster_name}-app2-policy"
  description = "Consumer-only dozvole za app2 da cita poruke iz svog SQS queue-a"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowConsumeApp2Queue"
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:GetQueueUrl",
          "sqs:ChangeMessageVisibility"
        ]
        Resource = aws_sqs_queue.app2_queue.arn
      }
    ]
  })

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "app2_role_attach" {
  role       = aws_iam_role.app2_role.name
  policy_arn = aws_iam_policy.app2_policy.arn
}

resource "aws_eks_pod_identity_association" "app2" {
  cluster_name    = module.eks.cluster_name
  namespace       = "default"
  service_account = "app2-sa"
  role_arn        = aws_iam_role.app2_role.arn

  depends_on = [module.eks]
}
