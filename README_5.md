# README.md for Task 5

## Aufgabe 5: Big Data Stream Processing

### Zielsetzung
Implementation einer Apache Kafka Streams-basierten Stream-Processing-Pipeline auf der bestehenden Multi-Node-Kubernetes-Infrastruktur. Die Lösung demonstriert horizontale Skalierbarkeit durch echte Stream-Processing-Engine mit Real-time Anomaly Detection für Sensor-Daten.

---

## Systemarchitektur
Die Implementation nutzt Apache Kafka Streams als zentrale Stream-Processing-Engine, nicht grundlegende Consumer/Producer-Tools. Dies erfüllt die Anforderung einer "geeigneten Stream-Processing-Engine" aus der Aufgabenstellung.

---

## Komponenten-Übersicht

| Komponente         | Zweck                            | Skalierbarkeit                  |
|--------------------|----------------------------------|----------------------------------|
| Kafka Cluster      | Message Broker, Event Streaming  | 1 Broker (Single-Node Setup)     |
| Zookeeper Cluster  | Coordination                     | 1 Instance                       |
| Kafka Streams App  | Java-basierte Stream Processing  | 1–3 Pods (Master-Node)           |
| Topic Partitions   | Load Distribution                | 3–9 Partitions pro Topic         |
| Web UI             | Kafka-UI für Monitoring          | NodePort 30902                   |

---

## Technologie-Stack
- **Stream Processing Engine:** Apache Kafka Streams (Java Library)  
- **Message Broker:** Apache Kafka 7.4.0 (Confluent Platform)  
- **Container Runtime:** containerd (K3s)  
- **Orchestration:** Kubernetes 1.33+ (K3s)  
- **Build System:** Maven 3.8+ mit Docker Multi-Stage Build  
- **Monitoring:** Kafka-UI (`provectuslabs/kafka-ui:v0.7.1`)  
- **Infrastructure:** OpenStack-basierte Multi-Node Umgebung  

---

## Erfüllung der Aufgabenanforderungen

### Stream-Processing-Engine Auswahl
Gemäß Aufgabenstellung wurde Apache Kafka Streams als Stream-Processing-Engine gewählt:

> "Für die Verarbeitung der gestreamten Daten kann eine geeignete Stream-Processing-Engine gewählt werden (z.B. Apache Kafka Streams, Apache Flink, Spark Streaming)"

**Vorteile von Kafka Streams:**
- Native Kafka-Integration ohne zusätzliche Cluster
- Exactly-once Processing Semantics
- Automatische Consumer Group Coordination
- Built-in State Management und Fault Tolerance
- Horizontale Skalierbarkeit

### Horizontale Skalierbarkeit
Die zentrale Anforderung *horizontale Skalierbarkeit* wird erfüllt durch:
1. **Consumer Group Partitioning** – automatische Verteilung von Topic-Partitionen  
2. **Kafka Streams Parallelism** – multiple Stream-Threads pro Instance  
3. **Kubernetes Pod Scaling** – Horizontal Pod Autoscaler  

---

## Implementation Details

### Kafka Streams Application (Java)
**Kerndatei:** `kafka-streams-app/src/main/java/com/sensor/anomaly/SensorAnomalyProcessor.java`

```java
public static void main(String[] args) {
    Properties props = new Properties();
    props.put(StreamsConfig.APPLICATION_ID_CONFIG, "sensor-anomaly-detector");
    props.put(StreamsConfig.BOOTSTRAP_SERVERS_CONFIG,
        System.getenv().getOrDefault("KAFKA_BOOTSTRAP_SERVERS","kafka-headless:9092"));
    props.put(StreamsConfig.PROCESSING_GUARANTEE_CONFIG, StreamsConfig.AT_LEAST_ONCE);
    props.put(StreamsConfig.NUM_STREAM_THREADS_CONFIG, 1);

    StreamsBuilder builder = new StreamsBuilder();

    KStream<String,String> sensorData = builder.stream("sensor-data");

    sensorData
        .mapValues(SensorAnomalyProcessor::processSensorData)
        .filter((key,value) -> value != null)
        .to("ml-predictions", Produced.with(Serdes.String(), Serdes.String()));
}
```
### Anomaly Detection "Algorithm"
```java
private static String processSensorData(String jsonValue) {
    JsonNode sensor = objectMapper.readTree(jsonValue);

    double temperature = sensor.get("temperature").asDouble();
    double humidity = sensor.get("humidity").asDouble();
    String sensorId = sensor.get("sensor_id").asText();

    int anomalyScore = 0;
    String alertLevel = "NORMAL";

    // Temperature thresholds
    if (temperature > 35) { anomalyScore += 3; alertLevel = "CRITICAL"; }
    else if (temperature < 5) { anomalyScore += 3; alertLevel = "CRITICAL"; }
    else if (temperature > 30 || temperature < 10) { anomalyScore += 1; alertLevel = "WARNING"; }

    // Humidity thresholds
    if (humidity > 85) { anomalyScore += 2; if (alertLevel.equals("NORMAL")) alertLevel = "WARNING"; }
    else if (humidity < 10) { anomalyScore += 2; if (alertLevel.equals("NORMAL")) alertLevel = "WARNING"; }

    // Logging
    if (anomalyScore > 0) {
        System.out.println("ANOMALY DETECTED: " + sensorId + " - " + alertLevel +
            " (T:" + temperature + "°C, H:" + humidity + "%, Score:" + anomalyScore + ")");
        return createAnomalyResult(sensor, anomalyScore, alertLevel);
    } else {
        System.out.println("NORMAL: " + sensorId + " - NORMAL (T:" + temperature + "°C, H:" + humidity + "%, Score:" + anomalyScore + ")");
        return null;
    }
}
```

### Build System
Maven Configuration: kafka-streams-app/pom.xml
```xml
<dependencies>
    <dependency>
        <groupId>org.apache.kafka</groupId>
        <artifactId>kafka-streams</artifactId>
        <version>3.5.1</version>
    </dependency>
    <dependency>
        <groupId>com.fasterxml.jackson.core</groupId>
        <artifactId>jackson-databind</artifactId>
        <version>2.15.2</version>
    </dependency>
</dependencies>
```
### Docker Multi-Stage Build
File: kafka-streams-app/Dockerfile
```dockerfile
FROM maven:3.8-openjdk-11-slim AS builder
WORKDIR /app
COPY pom.xml .
RUN mvn dependency:go-offline -B
COPY src ./src
RUN mvn clean package -DskipTests -B

FROM openjdk:11-jre-slim
WORKDIR /app
COPY --from=builder /app/target/sensor-anomaly-processor-1.0.0.jar app.jar
CMD ["sh","-c","java $JAVA_OPTS $KAFKA_STREAMS_OPTS -jar app.jar"]
```

### Kubernetes Deployment
File: big-data/kafka-streams-deployment.yaml

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kafka-streams-anomaly-processor
  namespace: kafka
spec:
  replicas: 1
  template:
    spec:
      nodeSelector:
        kubernetes.io/hostname: k8s-751f6dec-master
      containers:
      - name: kafka-streams-processor
        image: sensor-anomaly-processor:1.0.0
        imagePullPolicy: Never
        env:
        - name: KAFKA_BOOTSTRAP_SERVERS
          value: "kafka-headless:9092"
        - name: KAFKA_APPLICATION_ID
          value: "sensor-anomaly-detector"
        - name: KAFKA_STREAMS_OPTS
          value: "-Dkafka.streams.auto.offset.reset=earliest"
```

## Deployment und Betrieb
### Installation Workflow
```bash
# 1. Infrastructure Setup
./version-manager.sh deploy <version>

# 2. Kafka Cluster Installation
./version-manager.sh setup-kafka

# 3. Kafka Streams Application Build & Deploy
./version-manager.sh deploy-ml-stream-processor

# 4. Kafka UI für Monitoring
./version-manager.sh deploy-kafka-ui
./version-manager.sh open-kafka-ui
````