External Secrets Operator (ESO) – Helm Installation
External Secrets Operator (ESO) is a Kubernetes operator that enables Kubernetes Secrets to be sourced from external secret management systems such as AWS Systems Manager Parameter Store or AWS Secrets Manager.

It allows sensitive configuration data to be managed outside of the Kubernetes cluster while still being consumed by applications as standard Kubernetes Secrets.

This repository contains the minimal configuration used to install External Secrets Operator (ESO) via Helm.

Helm Repository:
helm repo add external-secrets https://charts.external-secrets.io
helm repo update


Installation:
ESO is installed using a custom values.yaml file to override only the required settings.

helm install external-secrets \
   external-secrets/external-secrets \
   --values values.yaml \
   -n external-secrets \
   --create-namespace
Chart version used: external-secrets 1.2.1 (app version v1.2.1)

Custom values
Only custom overrides are defined. All other settings use chart defaults.

values.yaml file:

global:
  tolerations:
    - key: "CriticalAddonsOnly"
      operator: "Exists"
      effect: "NoSchedule"


Notes:

global.tolerations ensures all ESO components (controller, webhook, cert-controller) can be scheduled on nodes with the CriticalAddonsOnly taint.

Namespace creation is handled automatically by Helm.



Validation
After installation, verify that ESO CRDs are installed:

k get crd --sort-by=.metadata.creationTimestamp --no-headers | tac | grep external-secrets
clustersecretstores.external-secrets.io                     2026-01-19T15:04:07Z
secretstores.external-secrets.io                            2026-01-19T15:04:07Z
uuids.generators.external-secrets.io                        2026-01-19T15:04:05Z
fakes.generators.external-secrets.io                        2026-01-19T15:04:05Z
cloudsmithaccesstokens.generators.external-secrets.io       2026-01-19T15:04:05Z
stssessiontokens.generators.external-secrets.io             2026-01-19T15:04:05Z
sshkeys.generators.external-secrets.io                      2026-01-19T15:04:05Z
clusterexternalsecrets.external-secrets.io                  2026-01-19T15:04:05Z
clustergenerators.generators.external-secrets.io            2026-01-19T15:04:05Z
vaultdynamicsecrets.generators.external-secrets.io          2026-01-19T15:04:05Z
gcraccesstokens.generators.external-secrets.io              2026-01-19T15:04:05Z
passwords.generators.external-secrets.io                    2026-01-19T15:04:05Z
githubaccesstokens.generators.external-secrets.io           2026-01-19T15:04:05Z
quayaccesstokens.generators.external-secrets.io             2026-01-19T15:04:05Z
pushsecrets.external-secrets.io                             2026-01-19T15:04:05Z
grafanas.generators.external-secrets.io                     2026-01-19T15:04:05Z
externalsecrets.external-secrets.io                         2026-01-19T15:04:05Z
webhooks.generators.external-secrets.io                     2026-01-19T15:04:05Z
ecrauthorizationtokens.generators.external-secrets.io       2026-01-19T15:04:05Z
mfas.generators.external-secrets.io                         2026-01-19T15:04:05Z
acraccesstokens.generators.external-secrets.io              2026-01-19T15:04:05Z
generatorstates.generators.external-secrets.io              2026-01-19T15:04:05Z
clusterpushsecrets.external-secrets.io                      2026-01-19T15:04:05Z


Verify that all ESO deployments are available:
kubectl get deployments -n external-secrets

The following components should be in Running state:

external-secrets
external-secrets-webhook
external-secrets-cert-controller