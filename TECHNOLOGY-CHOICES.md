# 🏗️ Technologie-Entscheidungen und Begründungen

> **Cloud Computing und Big Data - Portfolio-Prüfung**  
> Begründung der Technologieauswahl für die Immutable Infrastructure

## 📋 Überblick

Dieses Dokument begründet die bewussten Technologie-Entscheidungen für eine Immutable Infrastructure mit Multi-Node Kubernetes und KI-Anwendung.

---

## 🏗️ Infrastructure as Code: **Terraform**

**Warum gewählt:**
- **OpenStack-nativ** + Multi-Cloud-fähig
- **Deklarative Konfiguration** mit State Management
- **Terraform Workspaces** ermöglichen Zero-Downtime Deployments
- **Immutable Infrastructure** durch kompletten Ressourcenaustausch

**Alternativen:** Ansible (weniger für IaC), CloudFormation (AWS-only), Pulumi (weniger etabliert)

---

## ⚙️ Container Orchestration: **Kubernetes (K3s)**

**Warum gewählt:**
- **40% weniger Ressourcenverbrauch** als Standard K8s
- **Production-ready** mit allen K8s-Features
- **Eingebauter Traefik** Ingress Controller
- **Perfekt für OpenStack** mit 2-4 GB RAM

**Alternativen:** Standard K8s (zu ressourcenintensiv), Docker Swarm (weniger Features), OpenShift (zu komplex)

---

## 🌐 Ingress Controller: **Traefik**

**Warum gewählt:**
- **K3s-nativ** - vorkonfiguriert und sofort einsatzbereit
- **Cloud-Native Design** mit automatischer Service Discovery
- **Geringer Ressourcenverbrauch** + Hot-Reloading

**Alternativen:** NGINX Ingress (mehr Konfiguration), HAProxy (weniger Cloud-Native), Istio (zu komplex)

---

## 📦 Application Framework: **Streamlit**

**Warum gewählt:**
- **Rapid ML/AI Prototyping** - minimal Code für Web-Interface
- **Container-freundlich** mit einfacher Dockerisierung
- **Perfect für Google Gemini API** Integration

**Alternativen:** Flask/Django (mehr Entwicklungsaufwand), FastAPI (weniger UI-Features)

---

## 🤖 AI/ML Service: **Google Gemini 2.0 Flash API**

**Warum gewählt:**
- **Multimodal** (Text + Bild) für Kalorien-Schätzung
- **Kostenlos** + niedrige Latenz
- **Einfache Python SDK** Integration

**Alternativen:** OpenAI GPT-4V (kostenpflichtig), Azure Computer Vision (weniger spezifisch)

---

## 🔄 Deployment Strategy: **Zero-Downtime mit Terraform Workspaces**

**Warum gewählt:**
- **True Immutable Infrastructure** - komplette neue Infrastruktur
- **Risk Mitigation** - Health Checks + automatischer Rollback
- **Production-ready** - echte Zero-Downtime

---

## 🗄️ Objekt-Storage: **MinIO**

**Warum gewählt:**
- **Cloud-native** + nahtlose Integration mit Kubernetes
- **S3-kompatible API** für einfache Anbindung von SparkMLlib & scikit-learn
- **Leichtgewichtig** läuft als einzelner Service
- **Weniger Speicherverbrauch** Erasure Coding verbraucht weniger Speicher als n-Fache Replikation bei HDFS

**Alternativen:** Apache Hadoop HDFS (schwergewichtig, nicht cloud-native), Ceph (komplexere Verwaltung), AWS S3 (vendor lock-in)

---

## 🚀 Big Data Processing: **Apache Spark + MLlib**

**Warum gewählt:**
- **Verteilte Batch-Verarbeitung** für große Datensätze (50.000+ Samples)
- **Skalierbarkeit** durch distributed computing auf mehreren Cores
- **MLlib Integration** für Random Forest und K-Means Clustering
- **Spark SQL** für effiziente Feature Engineering

**Alternativen:** scikit-learn (nicht verteilbar), Hadoop MapReduce (komplexer), Dask (weniger etabliert)

---

## 🎯 Bonuspunkte-Features

- ✅ **K3s statt Standard K8s** - Ressourceneffizient + Production-ready
- ✅ **Zero-Downtime Deployments** - Terraform Workspaces
- ✅ **Ingress Controller** - Traefik für externe Erreichbarkeit  
- ✅ **HPA + Monitoring** - Prometheus + Grafana Stack
- ✅ **AI/ML Integration** - Google Gemini Bilderkennung
- ✅ **MinIO Datalake** - Cloud Nativer Datalake
