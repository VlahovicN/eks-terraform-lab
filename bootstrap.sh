#!/bin/bash
# End-to-end bootstrap: Terraform (VPC, EKS, IAM, ArgoCD) -> kubeconfig -> ArgoCD root Application.
# After the last step ArgoCD installs everything else from git (App-of-Apps).
#
# NOTE: this script is written for MY machine and is not meant to run as-is anywhere else.
# Adjust these to match your setup before using it:
#   - AWS_PROFILE below ("privatni" is my personal AWS CLI profile; use your own)
#   - the absolute paths (/home/nikola/learning) in the two `cd` commands
#   - the AWS region / cluster name if you changed them in the Terraform variables
# ArgoCD reads the manifests from GitHub, so push your changes to `main` before running this.
set -e

cd /home/nikola/learning/terraform-eks-infra

echo "=== 1. Terraform init, plan and apply ==="
export AWS_PROFILE="privatni"   # my personal AWS CLI profile - replace with your own
terraform init
terraform plan
terraform apply -auto-approve

echo "=== 2. Update kubeconfig ==="
aws eks update-kubeconfig --name eks-lab --region us-east-1 --alias eks-lab-personal

echo "=== 3. Setting environment variables ==="
export KARPENTER_NAMESPACE="kube-system"
export KARPENTER_VERSION="1.12.1"
export K8S_VERSION="1.35"
export AWS_PARTITION="aws"
export CLUSTER_NAME="eks-lab"
export AWS_DEFAULT_REGION="us-east-1"
export AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
export TEMPOUT="$(mktemp)"
export ALIAS_VERSION="$(aws ssm get-parameter --name "/aws/service/eks/optimized-ami/$K8S_VERSION/amazon-linux-2023/x86_64/standard/recommended/image_id" --query Parameter.Value | xargs aws ec2 describe-images --query 'Images[0].Name' --image-ids --region $AWS_DEFAULT_REGION | sed -r 's/^.*(v[[:digit:]]+).*$/\1/')"

echo "Checking variables:"
echo "$KARPENTER_NAMESPACE" "$KARPENTER_VERSION" "$K8S_VERSION" "$CLUSTER_NAME" "$AWS_DEFAULT_REGION" "$AWS_ACCOUNT_ID"


# JUST FOR THE REFERENCE
# curl -fsSL "https://raw.githubusercontent.com/aws/karpenter-provider-aws/v${KARPENTER_VERSION}/website/content/en/preview/getting-started/getting-started-with-karpenter/cloudformation.yaml" > "$TEMPOUT" \
#   && aws cloudformation deploy \
#     --stack-name "Karpenter-$CLUSTER_NAME" \
#     --template-file "$TEMPOUT" \
#     --capabilities CAPABILITY_NAMED_IAM \
#     --parameter-overrides "ClusterName=$CLUSTER_NAME"


echo "=== 4. Cleaning up stale Karpenter CRDs (if any) ==="
kubectl delete crd ec2nodeclasses.karpenter.k8s.aws nodepools.karpenter.sh nodeclaims.karpenter.sh nodeoverlays.karpenter.sh --ignore-not-found=true

echo "=== 5. Applying ArgoCD root Application (App-of-Apps: karpenter-crd, external-secrets, keda, karpenter, eks-lab-manifests) ==="
sleep 30
cd /home/nikola/learning
kubectl apply -f argocd/root.yaml


echo "=== DONE! ArgoCD is now syncing the rest from git (check: kubectl get application -n argocd) ==="