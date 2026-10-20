Project Structure for now: 

LEARNING/
├── helm/
│   ├── eso/
│   │   ├── README.md
│   │   └── values.yaml
│   └── karpenter/
│       └── values.yaml
├── argocd/
│   ├── root.yaml
│   └── apps/
│       ├── karpenter-crd.yaml
│       ├── external-secrets.yaml
│       ├── karpenter.yaml
│       └── eks-lab-manifests.yaml
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
  * Testiranje dinamičkog skaliranja (sa 0 na N i nazad) i provera kako Karpenter pali nove `t3.medium` nodove (uz granicu do 3-4 noda) - **čeka na quota increase, videti gore**.
* **Tačka 2: Kustomize Integracija — PAUZIRANO/PRESKOČENO**
  * Odlučeno da se preskoči: samo jedan lab cluster (jedan "dev" overlay) daje malu funkcionalnu vrednost, a Kustomize nije preduslov za ArgoCD (ArgoCD radi i sa plain YAML direktorijumom). Može se revizitirati kasnije ako se pojavi realna potreba za više environment-a.
* **Tačka 3: GitOps / ArgoCD — kod gotov, čeka live test preko bootstrap.sh**
  * **Application-i (u `argocd/apps/`):** `karpenter-crd`, `karpenter` (OCI chart-ovi) i `external-secrets` preuzimaju instalaciju Helm chart-ova koji su ranije isli rucno preko `bootstrap.sh` (`helm upgrade --install`), a `eks-lab-manifests` prati `k8s-gitops-manifests/`. Values su inline-ovani u samim Application manifestima (dupliraju `helm/karpenter/values.yaml` i `helm/eso/values.yaml` - remote Helm izvor ne moze da cita `valueFile` iz ovog git repoa). `bootstrap.sh` ne primenjuje ih vise pojedinacno, nego preko `argocd/root.yaml` (vidi App-of-Apps ispod). **Live testirano (dok su se primenjivali pojedinacno, pre App-of-Apps):** sva 4 Application-a (`karpenter-crd`, `karpenter`, `external-secrets`, `eks-lab-manifests`) su `Synced`+`Healthy`. OCI `repoURL` sintaksa (`public.ecr.aws/karpenter` bez `oci://` prefiksa, `chart:` posebno polje) radi. `external-secrets` je zahtevao `ServerSideApply=true` u `syncOptions`: ESO CRD-ovi (`ClusterSecretStore`, `SecretStore`) su preveliki za `kubectl.kubernetes.io/last-applied-configuration` anotaciju (limit 256KB) koju ArgoCD po defaultu (client-side apply) ugradi pri svakom apply-u, i na prvom kreiranju. Helm to ne pogađa jer koristi sopstveno praćenje release-a. Chart-ovi instalirani preko ArgoCD-a se NE vide u `helm list` (ArgoCD radi samo templating i sam primenjuje YAML, bez Helm release objekta); status se prati preko `kubectl get application -n argocd`. Env promenljive `KARPENTER_NAMESPACE`/`KARPENTER_VERSION` u koraku 3 su sada mrtve (vise se ne koriste), ostavljene za sada.
  * **Bug nadjen i ispravljen (ranije):** `aws_eks_pod_identity_association.keda_operator` je imao `depends_on = [helm_release.keda]` - obrnut redosled (Helm chart/keda-operator pod se pravio PRE nego sto Association postoji), pa je pod svaki put na svez apply padao na node-ov EC2 instance role (bez SQS dozvola) umesto na svoju Pod Identity rolu - isti simptom kao onaj `provider: aws-eks` bug od ranije, samo drugi uzrok. Ispravljeno okretanjem zavisnosti (`helm_release.keda` sad zavisi od asocijacije, ne obrnuto) u `eks.tf` - sprecava ponavljanje na buducim `bootstrap.sh` pokretanjima od nule. Na VEC zivom klasteru i dalje treba rucni `kubectl -n keda rollout restart deployment keda-operator` (Terraform depends_on promena ne dira postojece resurse).
  * **App-of-Apps (primenjeno, NIJE JOS TESTIRANO live):** `argocd/root.yaml` je jedini Application koji `bootstrap.sh` primenjuje (korak 5). Gleda `argocd/apps/` u gitu, gde su 4 child Application-a (zamenili stare `application.yaml` i `infra-helm-charts.yaml`). Wave anotacije na child `Application` objektima: `karpenter-crd` 0, `external-secrets` 0, `karpenter` 1, `eks-lab-manifests` 2. Tako CRD-ovi stignu pre CR-ova (`NodePool`, `ClusterSecretStore`...), što sync waves unutar jednog Application-a nisu mogli da reše. Za to je u `argocd.tf` dodata custom health provera za `Application` (`configs.cm."resource.customizations.health.argoproj.io_Application"`), bez koje wave ne čeka da child postane `Healthy`. Proveriti na prvom pokretanju da li je ta provera zaista potrebna i da li radi. Child manifesti se čitaju iz GitHub-a, pa ih treba commit-ovati i push-ovati pre `bootstrap.sh`. Finalizer za cascade brisanje namerno NIJE dodat (brisanje fajla iz `apps/` ne briše resurse tog child-a).
  * **Ako sync ipak zapne (stari problem):** neuspeli sync se NE ponavlja sam za isti commit; ručni sync: `kubectl patch application eks-lab-manifests -n argocd --type merge -p '{"operation":{"sync":{"prune":true}}}'`.
* **Tačka 4: Portfolio polish (pred javni repo)**
  * GitHub Actions CI (terraform fmt/validate, tflint, kubeconform/yamllint) - **preostaje**.
* **Tačka 5: ArgoCD napredno — SAMO NAKON što se prođe u kursu (ne radi se unapred)**
  * **Sync waves (već primenjeno, na zahtev, ranije od plana):** wave 0 `ClusterSecretStore` + `EC2NodeClass` (oba), wave 1 `ExternalSecret` + `NodePool` (oba), wave 2 `ServiceAccount app2-sa`, oba `Deployment`-a, oba `PodDisruptionBudget`-a + `TriggerAuthentication`, wave 3 `ScaledObject` (anotacija `argocd.argoproj.io/sync-wave` u metadata). **NIJE JOS TESTIRANO live.** Nije proveren ni da li ArgoCD ima ugrađenu health proveru za `ExternalSecret`; ako nema, wave daje samo redosled primene, a ne čekanje da secret stvarno postoji.
  * **App-of-Apps:** već primenjeno (vidi Tačku 3), ne čeka kurs. **ApplicationSet** za sada ne treba (jedan klaster, 4 Application-a); opciono za vežbu: Git directory generator nad `k8s-gitops-manifests/*` (po jedan Application po komponenti), ali bi to zamenilo `recurse: true`, ne dopunilo App-of-Apps.
  * **AppProject**: odlučeno da se preskoči (jedan korisnik, jedan klaster, `project: default` je dovoljan). Opciono za kraj kursa: podela na `infra` i `apps` projekat radi učenja/portfolija.
  * **Argo Rollouts (canary/blue-green)**: NE primenjivati na `app1`/`app2` (placeholder `sleep infinity` podovi bez Service-a i saobraćaja, a app2 skalira KEDA). Ako se vežba za kurs, raditi kao izolovan demo (npr. nginx + Service u zasebnom namespace-u i Application-u), odvojeno od lab infrastrukture.
