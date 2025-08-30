# 🚀 Kubernetes Multi-Node Cluster mit Zero-Downtime Deployments

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Terraform](https://img.shields.io/badge/Terraform-1.0+-blue.svg)](https://terraform.io)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-K3s-326CE5.svg)](https://k3s.io)
[![OpenStack](https://img.shields.io/badge/OpenStack-Cloud-red.svg)](https://openstack.org)
[![Datalake](https://img.shields.io/badge/Datalake-MinIO-purple.svg)](https://www.min.io/)
[![Apache Spark (Spark MLlib)](https://img.shields.io/badge/Batch_Verarbeitung-SparkMLlib-red.svg)](https://spark.apache.org/mllib/)
[![Apache Kafka](https://img.shields.io/badge/Stream_Processing-ApacheKafka-231F20.svg)](https://kafka.apache.org/)

> **Ein vollständiges Cloud Computing Projekt mit Immutable Infrastructure, Multi-Node Kubernetes, Zero-Downtime Deployments, Ingress Controller und KI-basierter Streamlit-Anwendung**

## 📖 Überblick

Dieses Projekt implementiert eine **Immutable Infrastructure** auf OpenStack mit einem Multi-Node Kubernetes-Cluster, der eine KI-gestützte Kalorien-Schätzungs-App mit Streamlit und Google Gemini API hostet.

### 🎯 Projektumfang

Das Projekt erfüllt **alle Anforderungen** der Portfolio-Prüfung "Cloud Computing und Big Data" und geht darüber hinaus:

- ✅ **Aufgabe 1**: Immutable Infrastructure mit Terraform
- ✅ **Aufgabe 2**: Configuration Management und Deployment-Versionierung  
- ✅ **Aufgabe 3**: Multi-Node Kubernetes-Architektur mit skalierbarer Anwendung
- ✅ **Aufgabe 4**: Data Lake / Big Data-Processing

## 🏗️ Architektur

```
┌─────────────────────────────────────────────────────────────────┐
│                     OpenStack Cloud                             │
├─────────────────────────────────────────────────────────────────┤
│  ┌─────────────┐    ┌─────────────┐ ┌─────────────┐ ┌────────┐  │
│  │ K8s Master  │    │ K8s Worker1 │ │ K8s Worker2 │ │ Ingress│  │
│  │             │    │             │ │             │ │        │  │
│  │ - K3s       │◄───┤ - K3s Agent │ │ - K3s Agent │ │Traefik │  │
│  │ - Docker    │    │ - Docker    │ │ - Docker    │ │        │  │
│  │ - Prometheus│    │ - App Pods  │ │ - App Pods  │ │ :80    │  │
│  │ - Grafana   │    │ - HPA       │ │ - HPA       │ │        │  │
│  └─────────────┘    └─────────────┘ └─────────────┘ └────────┘  │
│         │                                                       │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │     Zero-Downtime Deployment with Terraform Workspaces      ││
│  │     Blue-Green Strategy + Health Checks + Auto-Rollback     ││
│  └─────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────┘
                         │
               ┌──────────────────────┐
               │ External Access:     │
               │ • HTTP: :80 (Ingress)│
               │ • NodePort: :30001   │
               │ • Grafana: :30300    │
               │ • Prometheus: :30090 │
               └──────────────────────┘
```

### 🛠️ Technology Stack

| Komponente | Technologie | Zweck | Bonus-Feature |
|------------|-------------|-------|---------------|
| **Infrastructure as Code** | Terraform | Immutable Infrastructure Management | ✅ Workspaces für Zero-Downtime |
| **Container Orchestration** | Kubernetes (K3s) | Multi-Node Cluster Management | ✅ Lightweight Production K8s |
| **Ingress Controller** | Traefik | External Access & Load Balancing | ✅ Automatic SSL & Service Discovery |
| **Cloud Platform** | OpenStack | Compute, Network, Storage Resources | ✅ Multi-Cloud Ready |
| **Application Framework** | Streamlit | Web-basierte KI-Anwendung | ✅ Real-time ML Processing |
| **AI/ML** | Google Gemini 2.0 Flash API | Kalorien-Schätzung aus Bildern | ✅ Multimodal AI Integration |
| **Containerization** | Docker | Application Packaging | ✅ Multi-stage Builds |
| **Monitoring** | Prometheus + Grafana | Real-time Observability | ✅ HPA Metrics Integration |
| **Autoscaling** | Horizontal Pod Autoscaler | Dynamic Scaling | ✅ CPU + Memory Metrics |
| **Version Control** | Git + Semantic Versioning | Infrastructure & App Versioning | ✅ Zero-Downtime Deployments |
| **Datalake** | MinIO | Datenspeicherung | ✅ Cloud Nativer Datalake |
| **Big Data Processing** | Apache Spark + MLlib | Verteilte Batch-Verarbeitung | ✅ Skalierbare ML-Pipelines |
| **Stream Processing** | Apache Kafka | Echtzeit-Datenverarbeitung | ✅ Horizontale Skalierbarkeit + ML-Integration |

## 🚀 Quick Start

### Voraussetzungen

- OpenStack-Zugang mit Administrator-Rechten
- Terraform >= 1.0
- Git
- SSH-Key in OpenStack erstellt
- Docker (optional für lokale Entwicklung)

### Erste Installation

1. **Repository klonen**
   ```bash
   git clone <repository-url>
   cd cloud-computing-vl
   ```

2. **Setup ausführen**
   ```bash
   chmod +x setup.sh
   ./setup.sh
   ```

3. **OpenStack-Credentials konfigurieren**
   ```bash
   # Template zu openrc.sh kopiert - jetzt editieren
   vim openrc.sh
   # Oder: nano openrc.sh
   ```

4. **Terraform-Variablen konfigurieren**
   ```bash
   # Template zu terraform.tfvars kopiert - jetzt editieren  
   vim terraform.tfvars
   # Oder: nano terraform.tfvars
   ```

5. **Credentials laden und deployen**
   ```bash
   source openrc.sh
   ./version-manager.sh deploy v1.0
   ```

6. **Status überwachen**
   ```bash
   ./monitor.sh
   ```

### 🆘 Hilfe bei der Konfiguration

```bash
# Hilfe für OpenStack-Einstellungen
./help.sh

# Template-Dateien anzeigen
cat openrc.sh.template
cat terraform.tfvars.template
```

## 📋 Kommandos

### Version Manager

```bash
# 📋 Alle verfügbaren Versionen anzeigen
./version-manager.sh list

# 🚀 Spezifische Version deployen (Standard-Deployment)
./version-manager.sh deploy v1.0

# 🔄 Zero-Downtime Deployment (Produktions-bereit!)
./version-manager.sh zero-downtime v1.1

# 🏷️ Neue Version erstellen
./version-manager.sh create v1.1

# ⏪ Rollback zu vorheriger Version
./version-manager.sh rollback v1.0

# 📈 Anwendung skalieren
./version-manager.sh scale 5

# 📊 Cluster-Status anzeigen
./version-manager.sh status

# 📋 Application Logs anzeigen
./version-manager.sh logs

# 🧹 Infrastructure zerstören
./version-manager.sh cleanup
```

### 🔄 Zero-Downtime Deployment Features

```bash
# Erweiterte Zero-Downtime Deployment
./version-manager.sh zero-downtime v2.0
```

**Features:**
- 🏗️ **Parallele Infrastruktur**: Neue Version wird parallel zur alten aufgebaut
- 🏥 **Health Checks**: Automatische Gesundheitsprüfung vor Switch
- 🔄 **Auto-Rollback**: Bei Fehlern automatischer Rollback zur stabilen Version
- 💾 **State Backup**: Sichere Sicherung der aktuellen Infrastruktur
- ⚡ **Echter Zero-Downtime**: Keine Unterbrechung des Service

### Monitoring

```bash
# 🔍 Realtime Cluster Monitoring
./monitor.sh

# 📊 Einmaliger Status-Check
./version-manager.sh status

# 📊 Monitoring Dashboard öffnen
./version-manager.sh dashboard
```

### 🌐 External Access

Nach erfolgreichem Deployment sind folgende Services erreichbar:

```bash
# 🎯 Hauptanwendung (Streamlit)
http://MASTER-IP/           # Ingress (Port 80)
http://MASTER-IP:30001      # NodePort

# 📊 Monitoring
http://MASTER-IP:30300      # Grafana Dashboard (admin/admin)
http://MASTER-IP:30090      # Prometheus Metrics

# 🔐 SSH Access
ssh -i ~/.ssh/YOUR-KEY ubuntu@MASTER-IP
```

## 📊 Scaling Demo & Monitoring Dashboard

### 🎯 Automatisierte Scaling-Demonstration

Das Projekt enthält eine vollständige Scaling-Demo mit Grafana Dashboard für die Visualisierung der Horizontal Pod Autoscaler (HPA) Funktionalität.

#### Setup des Monitoring Dashboards

```bash
# 1. Dashboard importieren
./version-manager.sh import-dashboard

# 2. Monitoring Dashboard öffnen
./version-manager.sh monitoring
```

#### Scaling Demo ausführen

```bash
# Vollständige Scaling Demo mit Dashboard
./scaling-demo.sh
```

**Die Demo führt automatisch folgende Schritte aus:**

1. **📊 Monitoring Setup** - Überprüfung des Prometheus/Grafana Stacks
2. **🎛️ Dashboard Import** - Automatischer Import des Caloguessr Dashboard
3. **🌐 Browser-Integration** - Öffnet Grafana Dashboard automatisch (macOS)
4. **⚙️ Metrics Server** - Installation/Überprüfung der Kubernetes Metrics
5. **⚡ Load Generation** - Konfigurierbare Last-Generierung
6. **📈 Live Monitoring** - Echzeit-Überwachung der Skalierung

#### Monitoring URLs

Nach dem Deployment sind folgende Monitoring-Services verfügbar:

```bash
# Grafana Dashboard (admin/admin)
http://YOUR-MASTER-IP:30300

# Prometheus Metrics
http://YOUR-MASTER-IP:30090

# Caloguessr App
http://YOUR-MASTER-IP:30001
```

#### Dashboard Features

Das **Caloguessr Scaling Demo Dashboard** zeigt:

- 📊 **Pod Count & HPA Status** - Aktuelle vs. gewünschte Replicas
- 📈 **Pod Status Overview** - Live Status aller Pods (Running/Pending/Failed)
- 💻 **CPU Usage per Pod** - CPU-Verbrauch mit HPA-Schwellwerten
- 🧠 **Memory Usage per Pod** - Speicher-Verbrauch pro Pod
- 🌐 **Network I/O per Pod** - Netzwerk-Traffic während Load Tests
- 🔄 **HPA Scaling Events** - Visualisierung der Scaling-Ereignisse

#### Load Test Konfiguration

```bash
# Demo mit benutzerdefinierten Parametern
./scaling-demo.sh

# Interaktive Konfiguration:
# - Load Test Dauer (Standard: 600s = 10 Minuten)
# - Anzahl paralleler Requests (Standard: 100)
```

#### Typischer Scaling-Ablauf

1. **Baseline** - Start mit 2 Pods (HPA Minimum)
2. **Load Increase** - CPU-Last steigt über 10% Schwellwert
3. **Scaling Trigger** - HPA erhöht gewünschte Replicas
4. **Pod Creation** - Neue Pods werden erstellt
5. **Load Distribution** - Last verteilt sich auf mehr Pods
6. **Scale Down** - Nach Load-Ende: Pods werden reduziert

### 🔧 Monitoring-Kommandos

```bash
# Dashboard importieren/aktualisieren
./version-manager.sh import-dashboard

# Monitoring Dashboard öffnen
./version-manager.sh dashboard

# Live-Monitoring starten
./monitor.sh

# Manuelle Skalierung testen
./version-manager.sh scale 8

# HPA Status prüfen
./version-manager.sh status
```

### 📊 Metriken & Alerting

Das System überwacht automatisch:

- **Pod Metrics**: CPU, Memory, Network I/O
- **Cluster Health**: Node Status, Pod Phases
- **HPA Behavior**: Scaling Events, Target Metrics
- **Application Performance**: Response Times, Error Rates

## 📱 Anwendung

### Caloguessr - KI-Kalorien-Schätzer

Die Streamlit-Anwendung ermöglicht:

- 📸 **Bild-Upload** von Lebensmitteln
- 🧠 **KI-Analyse** mit Google Gemini API
- 📊 **Kalorien-Schätzung** und Nährwert-Analyse
- 🌐 **Web-Interface** über Browser
- 📱 **Responsive Design** für alle Geräte

#### Features

- ✨ **Benutzerfreundliche UI** mit Streamlit
- 🔐 **API-Key Management** über Web-Interface
- 📈 **Detaillierte Nährwert-Analyse**
- ⚡ **Schnelle Bildverarbeitung**
- 🔍 **Genauigkeits-Einschätzung**

## 🎯 Versionierung & Deployment

### Semantic Versioning

Das Projekt verwendet [Semantic Versioning](https://semver.org/):

```
v1.0.0 - Initial Release
├── v1.0.1 - Bugfixes
├── v1.1.0 - New Features  
└── v2.0.0 - Breaking Changes
```

### Entwicklungsworkflow

1. **Änderungen machen**
   ```bash
   # App-Code editieren
   vim app/caloguessr.py
   ```

2. **Neue Version erstellen**
   ```bash
   ./version-manager.sh create v1.1
   ```

3. **Deployen**
   ```bash
   ./version-manager.sh deploy v1.1
   ```

4. **Testen & Verifizieren**
   ```bash
   ./version-manager.sh status
   curl http://<MASTER-IP>:30001
   ```

5. **Bei Problemen: Rollback**
   ```bash
   ./version-manager.sh rollback v1.0
   ```

## 📊 Monitoring & Debugging

### Verfügbare Metriken

- 📊 **Cluster-Status** (Nodes, Pods, Services)
- 📈 **Resource Usage** (CPU, Memory)
- 🔗 **Application Health** (HTTP Response Codes)
- 📱 **Pod-Status** (Running, Pending, Failed)
- 🌐 **Service Connectivity** (Internal/External)

### Data Lake / Big Data-Processing

1. **Data Lake Setup ausführen**
   ```bash
   ./version-manager.sh setup-datalake
   ```

2. **Daten in Data Lake laden**
   ```bash
   ./version-manager.sh data-ingestion
   ```

3. **Apache Spark ML Pipeline ausführen**
   ```bash
   ./version-manager.sh spark-ml-pipeline
   ```

4. **Cleanup**
   ```bash
   ./version-manager.sh cleanup-ml-jobs
   ```

**Big Data Workflow:**
- **MinIO Data Lake**: S3-kompatibles Object Storage für große Datensätze
- **Data Ingestion**: Generiert 50.000+ Food-Samples und lädt sie in MinIO
- **Spark ML**: Verteilte Batch-Verarbeitung mit Apache Spark und MLlib
- **Zugriff**: MinIO Console unter `http://MASTER-IP:30901` (minioadmin/minioadmin123)

### Debugging

```bash
#  Application Logs
./version-manager.sh logs

# 🔧 Manuelle SSH-Verbindung (automatisch richtiger SSH-Key)
source openrc.sh
MASTER_IP=$(terraform output -raw master_ip)
SSH_KEY=$(grep "key_pair" terraform.tfvars | cut -d'"' -f2)
ssh -i ~/.ssh/$SSH_KEY ubuntu@$MASTER_IP
```

### Häufige Probleme

| Problem | Symptom | Lösung |
|---------|---------|--------|
| **SSH-Verbindung fehlschlägt** | Connection refused | SSH-Key Name in terraform.tfvars prüfen |
| **SSH-Key nicht gefunden** | Permission denied | Prüfen ob `~/.ssh/YOUR-KEY` existiert |
| **App startet nicht** | Pods in `Pending` Status | `./version-manager.sh logs` für Details |
| **OpenStack-Fehler** | Authentication failed | openrc.sh Credentials prüfen |
| **Workers joinen nicht** | Nur Master Node sichtbar | Cloud-init Logs prüfen |
| **Service nicht erreichbar** | 404/Connection Refused | Security Groups & NodePort prüfen |

### Big Data Stream Processing

1. **Stream Processing Setup ausführen**
   ```bash
   ./version-manager.sh setup-kafka
   ```

2. **Kafka Topics erstellen**
   ```bash
   ./version-manager.sh create-kafka-topic sensor-data 9 1
   ```

3. **Stream Prozessoren deployen**
   ```bash
   ./version-manager.sh deploy-ml-stream-processor
   ```

4. **Stream Demo starten**
   ```bash
   ./version-manager.sh kafka-stream-demo
   ```

5. **Kafka UI für Monitoring starten**
   ```bash
   ./version-manager.sh deploy-kafka-ui
   ./version-manager.sh open-kafka-ui
   ```

**Stream Processing Workflow:**
- **Apache Kafka Cluster**: Hochperformanter Message Broker für Echtzeit-Streaming
- **Horizontale Skalierbarkeit**: Partitionierte Topics (3, 6, 9 Partitionen) für parallele Verarbeitung
- **Stream Prozessoren**: Mehrere Prozessor-Instanzen für verteilte Event-Verarbeitung
- **ML-basierte Analyse**: Anomalieerkennung und Echtzeitüberwachung von Sensor-Daten
- **Management Interfaces**: Kafka-UI, Kafdrop und Kafka Manager für umfassendes Monitoring
- **Zugriff**: Kafka Manager unter `http://MASTER-IP:30900`, Kafka-UI unter `http://MASTER-IP:30902`

## 📚 Weiterführende Dokumentation

### Interne Dokumentation

- [`setup.sh`](./setup.sh) - Erstinstallation und Konfiguration
- [`help.sh`](./help.sh) - Hilfe für OpenStack-Einstellungen  
- [`version-manager.sh`](./version-manager.sh) - Hauptskript für Version Management
- [`monitor.sh`](./monitor.sh) - Cluster Monitoring
- [`scaling-demo.sh`](./scaling-demo.sh) - Automatisierte Scaling-Demo
- [`cloud-init-master.tpl`](./cloud-init-master.tpl) - Master Node Konfiguration
- [`main.tf`](./main.tf) - Terraform Infrastructure Definition
- [`grafana-dashboard-caloguessr.json`](./grafana-dashboard-caloguessr.json) - Grafana Dashboard Konfiguration
- [`datalake.yaml`](./big-data/datalake.yaml) - Datalake MinIO Konfiguration
- [`data-ingestion-job.yaml`](./big-data/data-ingestion-job.yaml) - Data Ingestion Konfiguration
- [`spark-ml-pipeline-job.yaml`](./big-data/spark-ml-pipeline-job.yaml) - Batch Verarbeitung Konfiguration

### Template-Dateien

- [`openrc.sh.template`](./openrc.sh.template) - OpenStack Credentials Template
- [`terraform.tfvars.template`](./terraform.tfvars.template) - Terraform Variables Template

### Externe Ressourcen

- [Terraform OpenStack Provider](https://registry.terraform.io/providers/terraform-provider-openstack/openstack/latest/docs)
- [K3s Documentation](https://docs.k3s.io/)
- [Streamlit Documentation](https://docs.streamlit.io/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [MinIO Documentation](https://www.min.io/)
- [Apache Spark Documentation](https://spark.apache.org/mllib/)
- [Apache Kafka Documentation](https://kafka.apache.org/documentation/)

## 📄 Lizenz

Dieses Projekt steht unter der MIT-Lizenz.

---

## 🎯 Projekt-Status

```bash
# Aktueller Status prüfen
./version-manager.sh status

# Letzte Version anzeigen  
./version-manager.sh list

# Monitoring Dashboard öffnen
./version-manager.sh dashboard

# Scaling Demo starten
./scaling-demo.sh
``` 
