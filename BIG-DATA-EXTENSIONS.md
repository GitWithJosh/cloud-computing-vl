# 🗂️📊 Big Data Erweiterungen: Aufgabe 4

> **Cloud Computing und Big Data - Portfolio-Prüfung**  
> Erweiterte Implementierung mit Data Lake, Stream Processing und ML

---

## 🏗️ **Erweiterte Infrastruktur mit Big Data Stack**

```
┌─────────────────────────────────────────────────────────────────┐
│                     OpenStack Cloud                             │
├─────────────────────────────────────────────────────────────────┤
│  ┌─────────────┐    ┌─────────────┐ ┌─────────────┐ ┌────────┐  │
│  │ K8s Master  │    │ K8s Worker1 │ │ K8s Worker2 │ │ Ingress│  │
│  │             │    │             │ │             │ │        │  │
│  │ - K3s       │◄───┤ - K3s Agent │ │ - K3s Agent │ │ Traefik│  │
│  │ - Docker    │    │ - Docker    │ │ - Docker    │ │        │  │
│  │ - Prometheus│    │ - App Pods  │ │ - App Pods  │ │ :80    │  │
│  │ - Grafana   │    │ - HPA       │ │ - HPA       │ │        │  │
│  └─────────────┘    └─────────────┘ └─────────────┘ └────────┘  │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │      Zero-Downtime Deployment with Terraform Workspaces     ││
│  │      Blue-Green Strategy + Health Checks + Auto-Rollback    ││
│  └─────────────────────────────────────────────────────────────┘│
│                                                                 │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │       Big Data Stack (Namespace: big-data)                  ││
│  │     - MinIO Data Lake (S3-kompatibel): :30900, :30901       ││
│  │     - Python ML Jobs (scikit-learn): Batch-Processing       ││
│  │     - Persistente Daten: raw-data, processed-data Buckets   ││
│  └─────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────┘

```

### **Big Data Tech Stack**

| Komponente | Technologie | Zweck | Integration |
|------------|-------------|-------|------------|
| **Object Storage** | MinIO | S3-kompatibel Data Lake | NodePort 30900, 30901 |
| **ML Processing** | Python scikit-learn | Batch ML Jobs auf K8s | K8s Job-Objekte |
| **Data Formats** | CSV, JSON, Parquet | Raw & Processed Data | MinIO Buckets |
| **Model Types** | Random Forest | Vorhersagemodelle | ML Pipeline |

## 🎯 **Überblick der Erweiterungen**

### **Aufgabe 4: Data Lake / Big Data-Processing** ✅ **VOLLSTÄNDIG IMPLEMENTIERT**
- ✅ **Verteilter Data Lake**: MinIO (S3-kompatibel) für Object Storage
- ✅ **Big Data Processing**: Python ML Jobs auf Kubernetes
- ✅ **Machine Learning**: scikit-learn für Food Calorie Analysis
- ✅ **Bonus Features**: Cloud-native Stack, horizontale Skalierung

---

## 🚀 **Quick Start für Aufgabe 4**

### **Setup Data Lake & Batch Processing**
```bash
# ⚠️  WICHTIG: Befehle in dieser Reihenfolge ausführen!

# 1. Data Lake installieren (ZUERST - erstellt big-data namespace + MinIO)
./version-manager.sh setup-datalake

# 2. ML Pipeline starten (benötigt setup-datalake!) 
./version-manager.sh ml-pipeline

# 3. Status prüfen (SSH erforderlich)
ssh -i ~/.ssh/$ssh_key ubuntu@$master_ip kubectl get pods -n big-data
ssh -i ~/.ssh/$ssh_key ubuntu@$master_ip kubectl get jobs -n big-data
```