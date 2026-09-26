# ArgoCD - pristup i objašnjenje (dev/lab setup)

## 1. Podaci za login

**Web UI**
- URL: `https://localhost:8080` (radi samo dok je `kubectl port-forward` aktivan, vidi korak 2 ispod)
- Username: `admin`
- Password: izvuci komandom ispod (menja se svaki put kad se cluster iznova podigne, jer je auto-generisan)
- Browser ce prikazati upozorenje za self-signed sertifikat - to je ocekivano, prihvati/nastavi (Advanced -> Proceed).

**CLI**
```bash
argocd login localhost:8080 --username admin --password '<password>' --insecure
```

## 2. Komande, korak po korak (redosled bitan)

```bash
# 1. Izvuci initial admin password iz K8s secret-a (base64-dekodiran)
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d

# 2. Otvori tunel ka argocd-server servisu (drzi terminal otvoren / pokreni u background-u)
kubectl port-forward svc/argocd-server -n argocd 8080:443

# 3. (novi terminal, tunel iz koraka 2 mora biti aktivan) Login preko CLI-a
argocd login localhost:8080 --username admin --password '<password-iz-koraka-1>' --insecure
```

## 3. Zasto se sve ovo radi (objasnjenje)

- **Zasto `argocd-initial-admin-secret`, ne neka lozinka koju sam ja postavio?**
  ArgoCD pri prvom pokretanju sam generise nasumicnu admin lozinku i cuva je (bcrypt hash) kao K8s Secret, dostupan samo onima koji imaju `kubectl` pristup namespace-u `argocd`. Ovo je bezbednije od hardkodovane default lozinke ("admin/admin") koju bi svako mogao da pogodi.

- **Zasto `kubectl port-forward`, a ne direktan pristup?**
  ArgoCD server po defaultu nije izlozen van clustera (`service.type: ClusterIP` - tako smo ga i podesili u `argocd.tf`, bas da ne pravi LoadBalancer/troshak). Port-forward otvara privremeni, enkriptovani tunel izmedju tvoje mašine i `argocd-server` pod-a KROZ postojecu `kubectl`/EKS autentikaciju - ne treba nikakav dodatni AWS resurs niti izlaganje na internet.

- **Zasto `--insecure` na CLI login-u?**
  ArgoCD server generise samoпотpisan (self-signed) TLS sertifikat po defaultu. `--insecure` govori CLI-u da ne provera da je sertifikat izdat od poznatog CA-a - prihvatljivo za localhost/dev tunel, NE za produkciju (vidi sekciju 4).

- **Zasto CLI login pored browser login-a?**
  UI je za rucno gledanje/klikanje (Applications, sync status, diff-ovi). CLI (`argocd app sync`, `argocd app create`, itd.) je za skriptovanje/automatizaciju i za ono sto cemo raditi kasnije kad pravimo `Application` resurse - oba koriste isti login/token mehanizam, samo razlicit interfejs.

## 4. Kako se ovo resava u produkciji

- **Bez port-forward-a.** UI se izlaze preko `Ingress` (ili internog `LoadBalancer`-a) sa pravim TLS sertifikatom (npr. preko cert-manager + Let's Encrypt, ili ACM ako je iza AWS ALB-a). Nema potrebe da svako drzi otvoren terminal/tunel.
- **Bez lokalnog admin login-a za svakodnevni rad.** ArgoCD ima ugradjen Dex server (vidimo `argocd-dex-server` pod da vec radi) koji omogucava SSO preko eksternog IdP-a (Okta, Google Workspace, GitHub/GitLab OAuth, Azure AD...). Ljudi se loguju svojim firma-nalogom, ne postoji deljena "admin" lozinka koju svi znaju.
- **RBAC vezan za SSO grupe**, ne za pojedinacne naloge - npr. "DevOps grupa" ima full pristup, "Dev grupa" samo read-only na svoje Application-e.
- **Initial admin secret se rotira/brise** nakon sto se SSO podesi - `argocd-initial-admin-secret` postoji samo kao "break glass" fallback, ne kao trajni nacin pristupa.
- **Mrezna izolacija** - UI/API cesto nije javno dostupan na internetu uopste (privatni ALB/Ingress, VPN, ili SSO provider koji vec zahteva da si na firma mrezi/VPN-u).
