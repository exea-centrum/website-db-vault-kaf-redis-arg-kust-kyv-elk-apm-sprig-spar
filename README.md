# website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-spar - Complete Monitoring Stack with Spring Boot, Spark & ELK

## 🛠️ Quick Start

## git clone https://github.com/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-spar.git

##

##

## git push

## put the content of yaml into argocd argocd-application.yaml

## He will download ArgoCD from github and handle everything

```bash
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-spar
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-spar.git
    targetRevision: HEAD
    path: manifests/base
  destination:
    server: https://kubernetes.default.svc
    namespace: davtroelkpyjs
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

```bash
# Generate all files
./lmarena.sh generate

# Deploy to Kubernetes
kubectl apply -k manifests/base

# Watch pods
kubectl -n davtroelkpyjs get pods -w

# Access applications:
# Main App: http://app.website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-spar.local
# New Survey: http://app.website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-spar.local/new-survey
# Spring Boot API: http://spring.website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-spar.local
# Spark UI: http://spark.website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-spar.local
# Kibana: http://kibana.website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-spar.local
# Grafana: http://grafana.website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-spar.local (admin/admin)
# PgAdmin: http://pgadmin.website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-spar.local (admin@example.com/adminpassword)
# Kafka UI: http://kafka-ui.website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-spar.local

# Initialize Vault
kubectl wait --for=condition=complete job/vault-init -n davtroelkpyjs

# Initialize MongoDB
kubectl wait --for=condition=complete job/mongodb-init -n davtroelkpyjs
```

## 🌐 Access Points

| Service                  | URL                                                                                    | Credentials                     |
| ------------------------ | -------------------------------------------------------------------------------------- | ------------------------------- |
| Application              | http://app.website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-spar.local            | -                               |
| New Survey (Spring Boot) | http://app.website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-spar.local/new-survey | -                               |
| Spring Boot API          | http://spring.website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-spar.local         | -                               |
| Spark Master UI          | http://spark.website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-spar.local          | -                               |
| Kibana                   | http://kibana.website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-spar.local         | -                               |
| Grafana                  | http://grafana.website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-spar.local        | admin/admin                     |
| PgAdmin                  | http://pgadmin.website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-spar.local        | admin@example.com/adminpassword |
| Kafka UI                 | http://kafka-ui.website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-spar.local       | -                               |

## 🏗️ Architecture Components:

### 1. **Python FastAPI Stack** (Original)

- **FastAPI Application** - Main web application with Vault integration
- **PostgreSQL** - Relational database for survey data
- **Redis** - Message queue for async processing
- **Kafka** - Event streaming platform
- **Vault** - Secrets management
- **Monitoring Stack** - Prometheus, Grafana, Loki, Tempo

### 2. **Java Spring Boot Stack** (New)

- **Spring Boot API** - REST API for new survey with MongoDB
- **MongoDB** - NoSQL database for survey responses
- **Apache Spark** - Real-time data processing and analytics
- **ELK Stack** - Elasticsearch, Logstash, Kibana for logging

### 3. **JavaScript Frontend** (New)

- **Modern JavaScript UI** - Interactive survey with React-like components
- **Chart.js** - Data visualization for survey statistics
- **Tailwind CSS** - Modern styling

## 🔧 Integration Details:

1. **Hybrid Architecture** - Python FastAPI + Java Spring Boot + JavaScript frontend
2. **Multiple Databases** - PostgreSQL (relational) + MongoDB (NoSQL)
3. **Real-time Processing** - Kafka + Apache Spark for data streaming
4. **Centralized Logging** - ELK Stack for logs from all components
5. **Unified Monitoring** - Prometheus + Grafana for all services
6. **Secrets Management** - HashiCorp Vault for all credentials

## 📊 Monitoring Stack:

- **Prometheus** - metrics collection from all services
- **Grafana** - unified dashboards with all datasources
- **Loki** - centralized log aggregation
- **Tempo** - distributed tracing
- **Postgres Exporter** - PostgreSQL metrics
- **MongoDB Exporter** - MongoDB metrics
- **Kafka Exporter** - Kafka metrics
- **Node Exporter** - system metrics

## 🔐 Security:

- All passwords in Vault
- Network policies for service communication
- Proper security contexts for databases
- Health checks and resource limits for all containers
- TLS/SSL ready configuration

## 🚀 Deployment Scripts:

```bash
# Full deployment
./deploy-extended.sh

# Check status
kubectl get pods -n davtroelkpyjs
kubectl get svc -n davtroelkpyjs
kubectl get ingress -n davtroelkpyjs
```

## 🔄 CI/CD Pipeline:

GitHub Actions automatically builds and deploys:

1. **Python FastAPI application**
2. **Spring Boot Java application**
3. **Apache Spark jobs**
4. **security-scan Dodałem job z kompleksowymi testami bezpieczeństwa:**

- SAST: CodeQL (Python, Java), Bandit (Python), SpotBugs (Java)
- Container Security: Trivy dla Dockerfile i zbudowanych obrazów. CVE-....
- Kubernetes Validation: kubeval dla manifestów
- Secret Scanning: TruffleHog
- Dependency Scanning: Safety dla Pythona
- DAST: OWASP ZAP z uruchamianiem testowych kontenerów
- Checkov: Skanuje manifesty Kubernetes i Dockerfile pod kątem błędnych konfiguracji (np. brak limitów CPU, praca na uprawnieniach roota).
- Hadolint: Specjalistyczny linter dla Dockerfile - wymusza najlepsze praktyki budowania obrazów.
- Gitleaks: Działa równolegle z TruffleHog, ale ma inne bazy sygnatur dla kluczy API, co zwiększa szansę na wykrycie "zaszytego" sekretu.
- pip-audit: Nowoczesna alternatywa dla Safety. Używa bazy PyPA, która jest często szybciej aktualizowana o nowe podatności w Pythonie.
- OWASP Dependency-Check: Złoty standard dla Javy. Skanuje plik pom.xml i pobiera dane z bazy NVD (National Vulnerability Database).
- Syft: Generuje SBOM (Software Bill of Materials). To plik JSON, który jest "paszportem" Twojego kontenera - zawiera listę każdej biblioteki zainstalowanej w obrazie.
  | Cecha | SAST | DAST | SCA | IAST |
  |--------------------|-------------------------------|-------------------------------|-------------------------------|-------------------------------|
  | **Podejście** | White-box (kod źródłowy) | Black-box (testy zewnętrzne) | Analiza zależności | Hybrydowe (kod + runtime) |
  | **Stan aplikacji** | Statyczny (aplikacja nie działa) | Dynamiczny (aplikacja działa) | Statyczny / Dynamiczny | Dynamiczny (agent w środku) |
  | **Koszt naprawy** | Najniższy (wczesna faza) | Średni / Wysoki | Zależy od wykrytej wersji | Średni |
  - actions/checkout@v4
    pobiera kod źródłowy repozytorium na maszynę runnera; bez tego nie ma czego budować ani skanować.
  - docker/login-action@v2
    loguje runnera do GitHub Container Registry (ghcr.io), żeby później móc „pushowa” obrazy.
  - docker/build-push-action@v4
    buduje obraz Docker według Dockerfile i od razu wypycha go do ghcr.io z podanymi tagami.
  - actions/setup-java@v3
    instaluje JDK (tu wersję 17) i Maven/Gradle; bez tego nie zbudujesz Springa.
  - olafurpg/setup-scala@v13
    instaluje Javę 11 oraz Scala/SBT; potrzebny do zbudowania jobów Sparka.
  - github/codeql-action/init@v3
    inicjalizuje silnik CodeQL (SAST) i przygotowuje go do analizy Pythona i Javy.
  - github/codeql-action/autobuild@v3
    próbuje samodzielnie skompilować projekt, żeby CodeQL mógł przeanalizować bytecode.
  - github/codeql-action/analyze@v3
    uruchamia właściwą analizę statyczną i wysyła wyniki do zakładki „Security” w repo.
  - hadolint/hadolint-action@v3.1.0
    lintuje Dockerfile - szuka błędów stylu, bezpieczeństwa i wydajności w instrukcjach Docker.
  - bridgecrewio/checkov-action@master
    skanuje infrastrukturę (Kubernetes, Dockerfile) pod kątem 750+ gotowych reguł bezpieczeństwa.
  - gitleaks/gitleaks-action@v2
    przeszuka historii gita w poszukiwaniu wyciekniętych sekretów (tokeny, klucze, hasła).
  - aquasecurity/trivy-action@master
    Trivy: skanuje pliki na dysku (fs), obrazy Docker i repozytoria pod kątem CVE (HIGH/CRITICAL).
  - actions/upload-artifact@v4
    zbiera wszystkie raporty (JSON, SARIF, HTML) z przebiegu i zapisuje je jako pliki do pobrania w UI GitHuba.
  - actions/setup-kustomize (wbudowany)
    instaluje narzędzie Kustomize, dzięki któremu można podmienić wersje obrazów w manifestach K8s

5. **Deploys to Kubernetes**

## 📈 Data Flow:

1. User submits survey via JavaScript frontend
2. Data sent to Spring Boot API via FastAPI proxy
3. Spring Boot saves to MongoDB and sends to Kafka
4. Apache Spark processes data in real-time
5. Results saved to MongoDB analytics collections
6. Logs sent to ELK Stack
7. Metrics collected by Prometheus
8. Visualizations in Grafana and Kibana

## 🐛 Troubleshooting:

```bash
# Check logs
kubectl logs -f deployment/fastapi-web-app -n davtroelkpyjs
kubectl logs -f deployment/spring-app -n davtroelkpyjs
kubectl logs -f deployment/spark-master -n davtroelkpyjs

# Check database connections
kubectl exec -it deployment/fastapi-web-app -n davtroelkpyjs -- python -c "import psycopg2; psycopg2.connect('dbname=webdb user=webuser password=testpassword host=postgres-db-normal port=5432')"
kubectl exec -it deployment/spring-app -n davtroelkpyjs -- curl http://localhost:8080/actuator/health

# Restart deployments
kubectl rollout restart deployment/fastapi-web-app -n davtroelkpyjs
kubectl rollout restart deployment/spring-app -n davtroelkpyjs
```

## 📚 Documentation:

- [FastAPI Documentation](https://fastapi.tiangolo.com/)
- [Spring Boot Documentation](https://spring.io/projects/spring-boot)
- [Apache Spark Documentation](https://spark.apache.org/docs/latest/)
- [ELK Stack Documentation](https://www.elastic.co/guide/index.html)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
# 🔹 Opcja 1 — włącz uprawnienia zapisu dla GITHUB_TOKEN

To najczystsze rozwiązanie.

Wejdź do repo:
👉 Settings → Actions → General → Workflow permissions

Zaznacz:
✅ Read and write permissions

Zapisz ustawienia.

Uruchom ponownie workflow (możesz zrobić git commit --allow-empty -m "retry" i push, żeby go wymusić).

To wystarczy — github-actions[bot] wtedy będzie mógł git push.

🔹 Opcja 2 — użyj personalnego tokena (PAT)

Jeśli nie chcesz zmieniać globalnych uprawnień, możesz użyć sekreta z Twoim PAT-em.

Utwórz PAT z zakresem:

repo

workflow

write:packages

W repo GitHub → Settings → Secrets → Actions

utwórz sekret o nazwie GHCR_PAT (można użyć tego samego co do GHCR).

W workflow zamień:

Upewnij się, że istnieje sekret w namespace davtrokyverno01

Utwórz go w microk8s:

```bash
microk8s kubectl create secret docker-registry ghcr-secret \
  --docker-server=ghcr.io \
  --docker-username=exea-centrum \
  --docker-password=ghp_NT.....<twój_PAT_z_uprawnieniami_read:packages> \
  --docker-email=exea-centrum@gmail.com \
  --namespace davtroelkpyjs
```
## **🐋 2\. Poprawiony GitHub Actions workflow**

Oryginalny workflow działał, ale miał kilka błędów i braków bezpieczeństwa.

### **🔹 Było:**

`permissions:`  
 `contents: write`  
 `packages: write`

👉 **Za wysoko (w `jobs` powinno być, nie globalnie)**  
 👉 Zbyt szerokie uprawnienia.

### **🔹 Teraz:**

`permissions:`  
 `contents: read`  
 `packages: write`

✅ **Dlaczego:**  
 To minimalne i zalecane uprawnienia do publikowania obrazów w GHCR.  
 Dodatkowo — przeniosłem je do poziomu **globalnego** (poprawna składnia YAML GitHub Actions).

---
### **1\. Przygotowanie MicroK8s**

1. Sprawdź status MicroK8s:  
   bash

```console
   microk8s status \--wait-ready
```

2. Włącz moduły dns , ingress i registry:  
   bash

```console
   microk8s enable dns ingress registry
```

3. Włącz ArgoCD:  
   bash

```console
   microk8s enable argocd
```

```console

microk8s enable argocd
Infer repository community for addon argocd
Infer repository core for addon helm3
Addon core/helm3 is already enabled
Installing ArgoCD (Helm v5.34.3)
"argo" has been added to your repositories
Release "argo-cd" does not exist. Installing it now.
NAME: argo-cd
LAST DEPLOYED: Mon Jun  1 09:45:18 2026
NAMESPACE: argocd
STATUS: deployed
REVISION: 1
TEST SUITE: None
NOTES:
In order to access the server UI you have the following options:

1. kubectl port-forward service/argo-cd-argocd-server -n argocd 8080:443

    and then open the browser on http://localhost:8080 and accept the certificate

2. enable ingress in the values file `server.ingress.enabled` and either
      - Add the annotation for ssl passthrough: https://argo-cd.readthedocs.io/en/stable/operator-manual/ingress/#option-1-ssl-passthrough
      - Set the `configs.params."server.insecure"` in the values file and terminate SSL at your ingress: https://argo-cd.readthedocs.io/en/stable/operator-manual/ingress/#option-2-multiple-ingress-objects-and-hosts


After reaching the UI the first time you can login with username: admin and the random password generated during the installation. You can find the password by running:

kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

(You should delete the initial secret afterwards as suggested by the Getting Started Guide: https://argo-cd.readthedocs.io/en/stable/getting_started/#4-login-using-the-cli)
ArgoCD is installed

```