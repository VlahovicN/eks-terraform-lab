#!/bin/bash
set -e

cd /home/nikola/learning/terraform-eks-infra

echo "=== 1. Terraform init, plan i apply ==="
export AWS_PROFILE="privatni"
terraform init
terraform plan
terraform apply -auto-approve

echo "=== 2. Update kubeconfig ==="
aws eks update-kubeconfig --name eks-lab --region us-east-1 --alias eks-lab-personal

echo "=== 3. Postavljanje environment promenljivih ==="
export KARPENTER_NAMESPACE="kube-system"
export KARPENTER_VERSION="1.12.1"
export K8S_VERSION="1.35"
export AWS_PARTITION="aws"
export CLUSTER_NAME="eks-lab"
export AWS_DEFAULT_REGION="us-east-1"
export AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
export TEMPOUT="$(mktemp)"
export ALIAS_VERSION="$(aws ssm get-parameter --name "/aws/service/eks/optimized-ami/$K8S_VERSION/amazon-linux-2023/x86_64/standard/recommended/image_id" --query Parameter.Value | xargs aws ec2 describe-images --query 'Images[0].Name' --image-ids --region $AWS_DEFAULT_REGION | sed -r 's/^.*(v[[:digit:]]+).*$/\1/')"

echo "Provera promenljivih:"
echo "$KARPENTER_NAMESPACE" "$KARPENTER_VERSION" "$K8S_VERSION" "$CLUSTER_NAME" "$AWS_DEFAULT_REGION" "$AWS_ACCOUNT_ID"


# JUST FOR THE REFERENCE
# curl -fsSL "https://raw.githubusercontent.com/aws/karpenter-provider-aws/v${KARPENTER_VERSION}/website/content/en/preview/getting-started/getting-started-with-karpenter/cloudformation.yaml" > "$TEMPOUT" \
#   && aws cloudformation deploy \
#     --stack-name "Karpenter-$CLUSTER_NAME" \
#     --template-file "$TEMPOUT" \
#     --capabilities CAPABILITY_NAMED_IAM \
#     --parameter-overrides "ClusterName=$CLUSTER_NAME"


echo "=== 4. Čišćenje starih CRD-ova (ako postoje) ==="
kubectl delete crd ec2nodeclasses.karpenter.k8s.aws nodepools.karpenter.sh nodeclaims.karpenter.sh nodeoverlays.karpenter.sh --ignore-not-found=true

echo "=== 5. Applying ArgoCD Application za infra Helm chart-ove (karpenter-crd, karpenter, external-secrets) ==="
sleep 30
cd /home/nikola/learning
kubectl apply -f argocd/infra-helm-charts.yaml

echo "=== 6. Applying ArgoCD Application za k8s-gitops-manifests (karpenter node-pools, eso, app1, app2) ==="
sleep 60
kubectl apply -f argocd/application.yaml


echo "=== SVE JE USPEŠNO ZAVRŠENO! ==="