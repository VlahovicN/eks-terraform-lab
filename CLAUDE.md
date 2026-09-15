Project Structure for now: 

LEARNING/
├── helm/
│   ├── eso/
│   │   ├── README.md
│   │   └── values.yaml
│   └── karpenter/
│       └── values.yaml
├── k8s-gitops-manifests/
│   ├── app1/
│   │   ├── deploy-app1.yaml
│   │   └── pdb-app1.yaml
│   ├── app2/
│   │   ├── deploy-app2.yaml
│   │   ├── scaledobject-app2.yaml
│   │   └── pdb-app2.yaml
│   ├── eso/
│   │   ├── clustersecretstore.yaml
│   │   ├── externalsecret.yaml
│   │   └── terraform.tfstate
│   └── karpenter/
│       ├── node-pool-priority.yaml
│       └── node-pool-standard.yaml
└── terra-form-eks-infra/ # (or terraform-eks-infra/)
    ├── .terraform/
    ├── .terraform.lock.hcl
    ├── beleske.txt
    ├── app2.tf
    ├── data.tf
    ├── eks.tf
    ├── iam.tf
    ├── karpenter.tf
    ├── koraci.txt
    ├── locals.tf
    ├── provider.tf
    ├── terraform.tfvars
    ├── variables.tf
    ├── vpc.tf
    ├── bootstrap.sh
    └── terraform.tfstate





# AWS EKS Lab - Status i Plan Projekta

## Šta je do sada urađeno

* **Infrastruktura i Terraform:** 
  * Podignut VPC, EKS klaster (`eks-lab`) i sve prateće IAM role.
* **Karpenter Autoscaling:** 
  * Instalirani CRD-ovi i Karpenter kontroler, podešeni nod pool-ovi (`node-pool-standard` i `node-pool-priority`) na `t3.medium` instancama uz strogu kontrolu resursa i troškova.
* **Secret Management (ESO):** 
  * Instaliran External Secrets Operator sa uspešno konfigurisanom vezom ka AWS Parameter Store-u (`ClusterSecretStore` i `ExternalSecret`).
* **KEDA (Kubernetes Event Driven Autoscaling)**
  * Uspešno instalirana KEDA u klaster.
* **Prva Aplikacija (`app1`):** 
  * Uspešno deployovana aplikacija koja uspešno povlači tajne preko ESO-a i radi na Karpenterovim čvorovima.
  * Fiksno na 3 replike + `PodDisruptionBudget` (`maxUnavailable: 1`).
* **Druga Aplikacija (`app2`) i KEDA ScaledObject:**
  * Deployovana aplikacija (SQS consumer-only Pod Identity rola preko Terraforma - `app2.tf`) na priority node pool-u, sa ESO integracijom (isti `eso-config` secret kao app1).
  * `TriggerAuthentication` + `ScaledObject` sa **Cron** (min 1 replika 08-20h Europe/Belgrade) i **SQS** (queueLength 5) trigerima. Auth ide preko `provider: aws` (EKS Pod Identity) - VAŽNO: `provider: aws-eks` je legacy/deprecated putanja koja ne radi sa nativnim EKS Pod Identity-jem (baca `awsAccessKeyID not found`), i KEDA operator pod mora biti restartovan nakon što mu se kreira Pod Identity Association (inače ne dobije injected AWS env promenljive).
  * `maxReplicaCount: 9`, resursi po podu (`cpu: 500m`, `memory: 900Mi`) namerno podešeni da stane tačno 3 poda po `t3.medium` nodu - cilj je da skaliranje KEDA (broj podova) i Karpenter (broj nodova) idu simultano kad se šalju SQS poruke (do 3 noda na vrhuncu).
  * `PodDisruptionBudget` (`maxUnavailable: 1`).
  * **Blokirano na AWS nalogu:** default EC2 "Running On-Demand Standard instances" vCPU kvota je 8, nedovoljno za dodatne priority nodove. Poslat je zahtev za povećanje na 16 vCPU (Service Quotas request ID `aa627511b9e4445c83bb468d6f13e294NspF86qe`, Support Case `178879883500574`) - status `CASE_OPENED`, čeka odobrenje više AWS timova. Live test skaliranja (slanje SQS poruka i provera da Karpenter pali nove nodove) čeka na ovo odobrenje.

---

## Plan daljih koraka (Roadmap)

* **Tačka 1: Deploy `app2` i KEDA Autoscaling** — kod gotov, čeka se AWS vCPU quota increase da se live testira
  * ~~Kreiranje deployment-a za drugu aplikaciju sa ESO integracijom.~~ ✅
  * ~~Implementacija KEDA `ScaledObject`-a sa kombinacijom **Cron + SQS** trigera.~~ ✅
  * Testiranje dinamičkog skaliranja (sa 0 na N i nazad) i provera kako Karpenter pali nove `t3.medium` nodove (uz granicu do 3-4 noda) - **čeka na quota increase, videti gore**.
* **Tačka 2: Kustomize Integracija — PAUZIRANO/PRESKOČENO**
  * Odlučeno da se preskoči: samo jedan lab cluster (jedan "dev" overlay) daje malu funkcionalnu vrednost, a Kustomize nije preduslov za ArgoCD (ArgoCD radi i sa plain YAML direktorijumom). Može se revizitirati kasnije ako se pojavi realna potreba za više environment-a.
* **Tačka 3: GitOps / ArgoCD — SLEDEĆE, čeka se da se nauči ArgoCD**
  * Instalacija ArgoCD-a u klaster, `Application` resurs koji direktno prati `k8s-gitops-manifests/` (plain YAML, bez Kustomize-a).
* **Tačka 4: Portfolio polish (pred javni repo)**
  * ~~Ukloniti tfstate fajlove iz repoa (obrisana 2 stray/leftover tfstate fajla), `.gitignore` dodat (`.terraform/`, `*.tfstate*`).~~ ✅
  * ~~`eks.tf` hardkodovan account ID u KEDA operator trust policy zamenjen sa `data.aws_caller_identity.current.account_id`.~~ ✅
  * ~~`helm/karpenter/values.yaml` - uklonjena mrtva IRSA `role-arn` anotacija (potvrđeno u kodu Karpenter modula da trust policy dozvoljava samo `pods.eks.amazonaws.com`, IRSA anotacija nikad nije mogla da radi - Karpenter koristi Pod Identity).~~ ✅
  * ~~`scaledobject-app2.yaml` SQS queue URL i dalje sadrži account ID - odlučeno da se NE parametrizuje (account ID nije secret), samo dodat inline komentar koji to objašnjava.~~ ✅
  * ~~README.md na engleskom (arhitektura, rationale, ne samo šta je urađeno).~~ ✅
  * GitHub Actions CI (terraform fmt/validate, tflint, kubeconform/yamllint) - **preostaje**.
  * ~~Git init, lokalni git identitet (licni email, ne firmin - podeseno samo `--local` za ovaj repo), push na `https://github.com/VlahovicN/eks-terraform-lab` (branch `main`).~~ ✅
