package com.sensor.anomaly;

import org.apache.kafka.streams.KafkaStreams;
import org.apache.kafka.streams.StreamsBuilder;
import org.apache.kafka.streams.StreamsConfig;
import org.apache.kafka.streams.kstream.KStream;
import org.apache.kafka.streams.kstream.Produced;
import org.apache.kafka.common.serialization.Serdes;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;

import java.util.Properties;
import java.time.Instant;
import java.util.concurrent.CountDownLatch;

public class SensorAnomalyProcessor {
    
    private static final ObjectMapper objectMapper = new ObjectMapper();
    
    public static void main(String[] args) {
        
        // Kafka Streams configuration
        Properties props = new Properties();
        props.put(StreamsConfig.APPLICATION_ID_CONFIG, "sensor-anomaly-detector");
        props.put(StreamsConfig.BOOTSTRAP_SERVERS_CONFIG, 
                 System.getenv().getOrDefault("KAFKA_BOOTSTRAP_SERVERS", "kafka-headless:9092"));
        props.put(StreamsConfig.DEFAULT_KEY_SERDE_CLASS_CONFIG, Serdes.String().getClass());
        props.put(StreamsConfig.DEFAULT_VALUE_SERDE_CLASS_CONFIG, Serdes.String().getClass());
        
        // Enable processing guarantees
        props.put(StreamsConfig.PROCESSING_GUARANTEE_CONFIG, StreamsConfig.AT_LEAST_ONCE);
        props.put(StreamsConfig.REPLICATION_FACTOR_CONFIG, 1); // Single broker setup
        props.put(StreamsConfig.NUM_STREAM_THREADS_CONFIG, 1); // Parallel processing
        
        // Build the topology
        StreamsBuilder builder = new StreamsBuilder();
        
        // Define the stream processing topology
        KStream<String, String> sensorData = builder.stream("sensor-data");
        
        sensorData
            // Transform each sensor reading
            .mapValues(SensorAnomalyProcessor::processSensorData)
            // Filter out null values (normal readings)
            .filter((key, value) -> value != null)
            // Send anomalies to output topic
            .to("ml-predictions", Produced.with(Serdes.String(), Serdes.String()));
        
        // Process user events for comprehensive monitoring
        KStream<String, String> userEvents = builder.stream("user-events");
        
        userEvents
            .mapValues(SensorAnomalyProcessor::processUserEvent)
            .filter((key, value) -> value != null)
            .to("ml-predictions", Produced.with(Serdes.String(), Serdes.String()));
        
        // Build and start the streams application
        KafkaStreams streams = new KafkaStreams(builder.build(), props);
        
        // Graceful shutdown
        final CountDownLatch latch = new CountDownLatch(1);
        
        Runtime.getRuntime().addShutdownHook(new Thread("streams-shutdown-hook") {
            @Override
            public void run() {
                System.out.println("Shutting down Kafka Streams application...");
                streams.close();
                latch.countDown();
            }
        });
        
        try {
            System.out.println("Starting Kafka Streams Sensor Anomaly Processor...");
            System.out.println("Application ID: " + props.getProperty(StreamsConfig.APPLICATION_ID_CONFIG));
            System.out.println("Bootstrap Servers: " + props.getProperty(StreamsConfig.BOOTSTRAP_SERVERS_CONFIG));
            System.out.println("Processing Topics: sensor-data, user-events -> ml-predictions");
            
            streams.start();
            System.out.println("Kafka Streams application started successfully!");
            
            latch.await();
        } catch (Exception e) {
            System.err.println("Error starting Kafka Streams: " + e.getMessage());
            e.printStackTrace();
            System.exit(1);
        }
    }
    
    private static String processSensorData(String jsonValue) {
        try {
            JsonNode sensor = objectMapper.readTree(jsonValue);
            
            double temperature = sensor.get("temperature").asDouble();
            double humidity = sensor.get("humidity").asDouble();
            String sensorId = sensor.get("sensor_id").asText();
            String originalTimestamp = sensor.get("timestamp").asText();
            
            // Anomaly detection algorithm
            int anomalyScore = 0;
            String alertLevel = "NORMAL";
            StringBuilder anomalyReasons = new StringBuilder("[");
            
            // Temperature thresholds
            if (temperature > 35) {
                anomalyScore += 3;
                alertLevel = "CRITICAL";
                anomalyReasons.append("\"HIGH_TEMPERATURE\"");
            } else if (temperature < 5) {
                anomalyScore += 3;
                alertLevel = "CRITICAL";
                anomalyReasons.append("\"LOW_TEMPERATURE\"");
            } else if (temperature > 30 || temperature < 10) {
                anomalyScore += 1;
                alertLevel = "WARNING";
                anomalyReasons.append("\"TEMP_WARNING\"");
            }
            
            // Humidity thresholds
            if (humidity > 85) {
                anomalyScore += 2;
                if ("NORMAL".equals(alertLevel)) alertLevel = "WARNING";
                if (anomalyReasons.length() > 1) anomalyReasons.append(",");
                anomalyReasons.append("\"HIGH_HUMIDITY\"");
            } else if (humidity < 10) {
                anomalyScore += 2;
                if ("NORMAL".equals(alertLevel)) alertLevel = "WARNING";
                if (anomalyReasons.length() > 1) anomalyReasons.append(",");
                anomalyReasons.append("\"LOW_HUMIDITY\"");
            }
            
            anomalyReasons.append("]");
            
            // Log all readings with clear distinction
            if (anomalyScore > 0) {
                // Log anomaly
                System.out.println("ANOMALY DETECTED: " + sensorId + " - " + alertLevel + 
                                " (T:" + temperature + "°C, H:" + humidity + "%, Score:" + anomalyScore + ")");
                
                // Create result for anomalous readings
                ObjectNode result = objectMapper.createObjectNode();
                result.put("timestamp", Instant.now().toString());
                result.put("original_timestamp", originalTimestamp);
                result.put("processor", "kafka-streams");
                result.put("ml_model", "threshold-anomaly-detector-v1.0");
                result.put("source", "sensor-data");
                result.put("sensor_id", sensorId);
                result.put("temperature", temperature);
                result.put("humidity", humidity);
                result.put("ml_prediction", anomalyScore > 2 ? "ANOMALY_DETECTED" : "WARNING_DETECTED");
                result.put("alert_level", alertLevel);
                result.put("anomaly_score", anomalyScore);
                result.put("anomaly_reasons", anomalyReasons.toString());
                result.put("processing_epoch", Instant.now().getEpochSecond());
                
                return objectMapper.writeValueAsString(result);
            } else {
                // Log normal reading
                System.out.println("NORMAL: " + sensorId + " - NORMAL (T:" + temperature + "°C, H:" + humidity + "%, Score:" + anomalyScore + ")");
                return null; // Normal readings are filtered out from output topic
            }
            
        } catch (Exception e) {
            System.err.println("Error processing sensor data: " + e.getMessage());
            return null;
        }
    }

    /**
     * Process user events for behavioral anomalies (simplified)
     */
    private static String processUserEvent(String jsonValue) {
        try {
            JsonNode event = objectMapper.readTree(jsonValue);
            
            int userId = event.get("user_id").asInt();
            String action = event.get("action").asText();
            int pageId = event.get("page_id").asInt();
            
            // Simple behavioral anomaly: high page access rate
            if (pageId > 45) { // Arbitrary threshold for demo
                // Log user anomaly
                System.out.println("USER ANOMALY: User " + userId + " accessing high page ID " + pageId + " - SUSPICIOUS_BEHAVIOR");
                
                ObjectNode result = objectMapper.createObjectNode();
                result.put("timestamp", Instant.now().toString());
                result.put("processor", "kafka-streams");
                result.put("ml_model", "user-behavior-detector-v1.0");
                result.put("source", "user-events");
                result.put("user_id", userId);
                result.put("action", action);
                result.put("page_id", pageId);
                result.put("ml_prediction", "SUSPICIOUS_BEHAVIOR");
                result.put("alert_level", "WARNING");
                result.put("anomaly_score", 1);
                result.put("anomaly_reasons", "[\"HIGH_PAGE_ACCESS\"]");
                result.put("processing_epoch", Instant.now().getEpochSecond());
                
                return objectMapper.writeValueAsString(result);
            } else {
                // Log normal user behavior
                System.out.println("USER NORMAL: User " + userId + " performed " + action + " on page " + pageId + " - NORMAL_BEHAVIOR");
                return null; // Normal user behavior filtered out
            }
            
        } catch (Exception e) {
            System.err.println("Error processing user event: " + e.getMessage());
            return null;
        }
    }
}