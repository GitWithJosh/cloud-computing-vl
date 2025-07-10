# 🗂️📊 Big Data Erweiterungen: Aufgabe 4

> **Cloud Computing und Big Data - Portfolio-Prüfung**  
> Erweiterte Implementierung mit Data Lake, Stream Processing und ML

---

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