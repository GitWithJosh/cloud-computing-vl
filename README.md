# 🚀 Kubernetes Multi-Node Cluster mit Streamlit Caloguessr App

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Terraform](https://img.shields.io/badge/Terraform-1.0+-blue.svg)](https://terraform.io)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-K3s-326CE5.svg)](https://k3s.io)
[![OpenStack](https://img.shields.io/badge/OpenStack-Cloud-red.svg)](https://openstack.org)

> **Ein vollständiges Cloud Computing Projekt mit Immutable Infrastructure, Multi-Node Kubernetes und KI-basierter Streamlit-Anwendung**

## 📖 Überblick

Dieses Projekt implementiert eine **Immutable Infrastructure** auf OpenStack mit einem Multi-Node Kubernetes-Cluster, der eine KI-gestützte Kalorien-Schätzungs-App mit Streamlit und Google Gemini API hostet.

### 🎯 Projektumfang

Das Projekt erfüllt alle Anforderungen der Portfolio-Prüfung "Cloud Computing und Big Data":

- ✅ **Aufgabe 1**: Immutable Infrastructure mit Terraform
- ✅ **Aufgabe 2**: Configuration Management und Deployment-Versionierung  
- ✅ **Aufgabe 3**: Multi-Node Kubernetes-Architektur mit skalierbarer Anwendung

## 🏗️ Architektur

```
┌─────────────────────────────────────────────────────┐
│                  OpenStack Cloud                    │
├─────────────────────────────────────────────────────┤
│  ┌─────────────┐    ┌─────────────┐ ┌─────────────┐ │
│  │ K8s Master  │    │ K8s Worker1 │ │ K8s Worker2 │ │
│  │             │    │             │ │             │ │
│  │ - K3s       │◄───┤ - K3s Agent │ │ - K3s Agent │ │
│  │ - Docker    │    │ - Docker    │ │ - Docker    │ │
│  │ - App Pods  │    │ - App Pods  │ │ - App Pods  │ │
│  └─────────────┘    └─────────────┘ └─────────────┘ │
│         │                                           │
│  ┌─────────────────────────────────────────────────┐ │
│  │        NodePort Service (30001)                 │ │
│  │     LoadBalancer + Horizontal Pod Autoscaler    │ │
│  └─────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────┘
                         │
               ┌─────────────────────┐
               │   External Access   │
               │ http://IP:30001     │
               └─────────────────────┘
```

### 🛠️ Technology Stack

| Komponente | Technologie | Zweck |
|------------|-------------|--------|
| **Infrastructure as Code** | Terraform | Immutable Infrastructure Management |
| **Container Orchestration** | Kubernetes (K3s) | Multi-Node Cluster Management |
| **Cloud Platform** | OpenStack | Compute, Network, Storage Resources |
| **Application Framework** | Streamlit | Web-basierte KI-Anwendung |
| **AI/ML** | Google Gemini API | Kalorien-Schätzung aus Bildern |
| **Containerization** | Docker | Application Packaging |
| **Version Control** | Git + Semantic Versioning | Infrastructure & App Versioning |

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
   cd cloud-computing-vl/cloud-project
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

# 🚀 Spezifische Version deployen
./version-manager.sh deploy v1.0

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

# 🔍 Cluster debuggen
./version-manager.sh debug

# 🧹 Infrastructure zerstören
./version-manager.sh cleanup
```

### Monitoring

```bash
# 🔍 Realtime Cluster Monitoring
./monitor.sh

# 📊 Einmaliger Status-Check
./version-manager.sh status
```

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

### Zugriff

Nach erfolgreichem Deployment:

```bash
# App-URL anzeigen
./version-manager.sh status

# Direkter Zugriff über Browser
open http://<MASTER-IP>:30001
```

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

### Debugging

```bash
# 🔍 Vollständige Debug-Informationen
./version-manager.sh debug

# 📋 Application Logs
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
| **App startet nicht** | Pods in `Pending` Status | `./version-manager.sh debug` |
| **OpenStack-Fehler** | Authentication failed | openrc.sh Credentials prüfen |
| **Workers joinen nicht** | Nur Master Node sichtbar | Cloud-init Logs prüfen |
| **Service nicht erreichbar** | 404/Connection Refused | Security Groups & NodePort prüfen |

## 📚 Weiterführende Dokumentation

### Interne Dokumentation

- [`setup.sh`](./setup.sh) - Erstinstallation und Konfiguration
- [`help.sh`](./help.sh) - Hilfe für OpenStack-Einstellungen  
- [`version-manager.sh`](./version-manager.sh) - Hauptskript für Version Management
- [`monitor.sh`](./monitor.sh) - Cluster Monitoring
- [`cloud-init-master.tpl`](./cloud-init-master.tpl) - Master Node Konfiguration
- [`main.tf`](./main.tf) - Terraform Infrastructure Definition

### Template-Dateien

- [`openrc.sh.template`](./openrc.sh.template) - OpenStack Credentials Template
- [`terraform.tfvars.template`](./terraform.tfvars.template) - Terraform Variables Template

### Externe Ressourcen

- [Terraform OpenStack Provider](https://registry.terraform.io/providers/terraform-provider-openstack/openstack/latest/docs)
- [K3s Documentation](https://docs.k3s.io/)
- [Streamlit Documentation](https://docs.streamlit.io/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)

## 📄 Lizenz

Dieses Projekt steht unter der MIT-Lizenz.

---

## 🎯 Projekt-Status

```bash
# Aktueller Status prüfen
./version-manager.sh status

# Letzte Version anzeigen  
./version-manager.sh list
```

**Aktuelle Version**: v1.0  

---

*Cloud Computing und Big Data - Portfolio-Prüfung*