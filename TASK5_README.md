# Aufgabe 5: Big Data Stream Processing mit Apache Kafka

```
                                    Kubernetes Cluster
┌───────────────────────────────────────────────────────────────────────────────┐  
│                                                                               │  
│  ┌─────────────┐              Apache Kafka Cluster                 ┌────────┐ │  
│  │             │           ┌───────────────────────┐               │        │ │  
│  │             │           │                       │   Skalierbar  │ Kafka  │ │  
│  │  Zookeeper  │◄────────►│  Kafka Broker(s)      │◄──────────────┤ Manager│ │  
│  │             │           │  - Port: 9092         │               │ UI     │ │  
│  │             │           │  - NodePort: 30092    │               │        │ │  
│  └─────────────┘           └───────────┬───────────┘               └────────┘ │  
│                                        │                                      │  
│                                        │                                      │  
│                                        ▼                                      │  
│                            ┌───────────────────────┐                          │  
│  ┌──────────────┐          │                       │                          │  
│  │ Demo Topic   │          │     Kafka Topics      │                          │  
│  │ Creation Job │─────────►│ - demo-topic (3P)     │                          │  
│  │              │          │ - user-events (6P)    │                          │  
│  └──────────────┘          │ - sensor-data (9P)    │                          │  
│                            │ - processed-events (3P)│                          │  
│                            └───────────┬───────────┘                          │  
│                                        │                                      │  
│                                        │                                      │  
│                                        ▼                                      │  
│                            ┌───────────────────────┐                          │  
│                            │                       │                          │  
│                            │    Stream Processing  │                          │  
│  ┌──────────────┐          │       Pipeline        │           ┌──────────┐   │  
│  │ Stream       │─────────►│  - Kafka Streams (2R) │───────────┤          │   │  
│  │ Processing   │          │  - [Bonus] Flink      │           │ Kafka-UI │   │  
│  │ Demo Job     │          │  - [Bonus] Spark      │           │          │   │  
│  └──────────────┘          └───────────────────────┘           └──────────┘   │  
│                                                                               │  
└───────────────────────────────────────────────────────────────────────────────┘  
```

**Legende:**
- P = Partitionen (für horizontale Skalierbarkeit)
- R = Replicas (horizontale Skalierung der Verarbeitung)

## Installation und Konfiguration

### Schritt 1: Kafka-Cluster installieren
Um den Kafka-Cluster zu installieren, verwenden wir unseren version-manager.sh:
```bash
./version-manager.sh setup-kafka
```

Dies installiert die folgenden Komponenten:

* Apache Kafka (Version 7.4.0)
* Zookeeper für die Koordination
* Kafka Manager für die UI-basierte Verwaltung
* Demo-Topics mit unterschiedlichen Partitionierungsgraden

Der Kafka-Cluster wird in einem dedizierten Kubernetes-Namespace `kafka` installiert, was eine klare Trennung der Ressourcen ermöglicht.

### Schritt 2: Überprüfen der Kafka-Installation
```bash
./version-manager.sh kafka-status
```

### Schritt 3: Kafka-Topic erstellen
```bash
./version-manager.sh create-kafka-topic my-events 6 1
```
Dieser Befehl erstellt einen Topic namens `my-events` mit 6 Partitionen und einem Replikationsfaktor von 1.

### Schritt 4: Verbesserte UI mit Kafka-UI bereitstellen
```bash
./version-manager.sh deploy-kafka-ui
```

## Kafka-Cluster Konfiguration

Unsere Kafka-Konfiguration in `kafka-cluster.yaml` wurde sorgfältig optimiert, um Stabilität und einfache Skalierbarkeit zu gewährleisten:

```yaml
# Kafka Deployment - Korrigierte Konfiguration ohne StatefulSet-Komplexität
spec:
  replicas: 1  # Horizontal skalierbar durch Anpassung von replicas
        # Horizontale Skalierbarkeit durch Partitionen
        - name: KAFKA_NUM_PARTITIONS
          value: "3"  # Default-Partitionen pro Topic
```

* `NUM_PARTITIONS: "3"` erlaubt parallele Verarbeitung der Daten
* Topics werden mit unterschiedlichen Partitionsanzahlen erstellt (3, 6, 9)
* Wir nutzen ein Deployment statt StatefulSet für einfachere Wartung

## Implementierung der Stream Processing Pipeline

### Schritt 1: Testdaten generieren mit dem Stream Processing Demo
```bash
./version-manager.sh kafka-stream-demo
```
Diese Funktion erzeugt kontinuierlich Testdaten in den folgenden Formaten:

* Sensor-Daten: Temperatur- und Feuchtigkeitswerte von simulierten IoT-Geräten
* Benutzer-Ereignisse: Nutzeraktivitäten wie Klicks und Seitenaufrufe

### Schritt 2: Stream Processing Pipeline bereitstellen
Wir implementieren eine horizontale Stream Processing Pipeline, die parallel arbeitet:

Die Kafka Streams Pipeline wird mit zwei Replikas gestartet, die folgende Funktionen erfüllen:

* Parallele Verarbeitung: Jede Instanz bearbeitet unterschiedliche Partitionen
* Echtzeitanalyse: Kontinuierliche Verarbeitung der eingehenden Datenströme
* Anreicherung: Hinzufügen von Verarbeitungsmetadaten zu Events
* Ausgabe: Schreiben der verarbeiteten Daten in den processed-events-Topic

### Schritt 3: Überprüfen der verarbeiteten Daten
```bash
./version-manager.sh kafka-show-streams
```
Dieses Kommando zeigt die verfügbaren Topics und Beispieldaten aus den jeweiligen Streams.

## Ergebnisse und Ausblick

### Erreichte Ziele
Unsere Implementierung hat erfolgreich:

✅ Einen horizontal skalierbaren Kafka-Cluster auf Kubernetes implementiert  
✅ Partitionierte Topics für parallele Verarbeitung erstellt  
✅ Eine skalierbare Stream Processing Pipeline mit mehreren Instances implementiert  
✅ Alternative Technologien (Flink, Spark Streaming) integriert (Bonuspunkt)  
✅ Echtzeitverarbeitung mit automatischer Partitionsverteilung demonstriert  
✅ Machine Learning-Integration vorbereitet (Bonuspunkt)  
✅ Management-UIs (Kafka Manager, Kafka-UI) für einfache Überwachung bereitgestellt  

### Monitoring und Management
Die Stream Processing Pipeline kann auf verschiedene Weisen überwacht werden:

```bash
# Stream Processing Status
./version-manager.sh stream-status

# Kafka Topic-Überwachung
./version-manager.sh kafka-show-streams

# UI-basierte Überwachung
./version-manager.sh open-kafka-ui
```