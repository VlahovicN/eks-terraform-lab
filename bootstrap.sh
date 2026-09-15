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

echo "=== 4. Čišćenje starih CRD-ova (ako postoje) ==="
kubectl delete crd ec2nodeclasses.karpenter.k8s.aws nodepools.karpenter.sh nodeclaims.karpenter.sh nodeoverlays.karpenter.sh --ignore-not-found=true

echo "=== 5. Instalacija Karpenter CRD-ova (Prvo ovo!) ==="
helm upgrade --install karpenter-crd oci://public.ecr.aws/karpenter/karpenter-crd \
    --version "$KARPENTER_VERSION" \
    --namespace "$KARPENTER_NAMESPACE" \
    --create-namespace

echo "=== 6. Instalacija Karpenter Kontrolera ==="
helm upgrade --install karpenter oci://public.ecr.aws/karpenter/karpenter \
    --version "$KARPENTER_VERSION" \
    -n "$KARPENTER_NAMESPACE" \
    -f ../helm/karpenter/values.yaml


echo "=== 7. Applying Karpenter Manifest yaml files"

cd /home/nikola/learning/k8s-gitops-manifests/karpenter
sleep 60
kubectl apply -f node-pool-standard.yaml
kubectl apply -f node-pool-priority.yaml


echo "=== 8. Instalacija External Secrets Operator-a (ESO) ==="
cd /home/nikola/learning/helm/eso

helm repo add external-secrets https://charts.external-secrets.io
helm repo update

helm upgrade --install external-secrets external-secrets/external-secrets \
    --values values.yaml \
    -n external-secrets \
    --create-namespace

echo "=== 9. Applying ESO Manifest yaml files"     
cd /home/nikola/learning/k8s-gitops-manifests/eso
sleep 30
kubectl apply -f clustersecretstore.yaml
kubectl apply -f externalsecret.yaml


echo "=== 10. Deploying app1 ==="
cd /home/nikola/learning/k8s-gitops-manifests/app1
kubectl apply -f deploy-app1.yaml
kubectl apply -f pdb-app1.yaml


echo "=== 11. Deploying app2 i KEDA ScaledObject ==="
cd /home/nikola/learning/k8s-gitops-manifests/app2
kubectl apply -f deploy-app2.yaml
kubectl apply -f scaledobject-app2.yaml
kubectl apply -f pdb-app2.yaml


echo "=== SVE JE USPEŠNO ZAVRŠENO! ==="