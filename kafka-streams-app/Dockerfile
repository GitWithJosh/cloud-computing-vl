# Multi-stage build for Kafka Streams application
FROM maven:3.8-openjdk-11-slim AS builder

# Set working directory
WORKDIR /app

# Copy Maven configuration first (for better Docker layer caching)
COPY pom.xml .

# Download dependencies (cached layer if pom.xml hasn't changed)
RUN mvn dependency:go-offline -B

# Copy source code
COPY src ./src

# Build the application
RUN mvn clean package -DskipTests -B

# Runtime stage - smaller image
FROM openjdk:11-jre-slim

# Add labels for better container management
LABEL maintainer="kafka-streams-app"
LABEL version="1.0.0"
LABEL description="Kafka Streams Sensor Anomaly Processor"

# Create app directory
WORKDIR /app

# Copy the built JAR from builder stage
COPY --from=builder /app/target/sensor-anomaly-processor-1.0.0.jar app.jar

# Create non-root user for security
RUN groupadd -r appuser && useradd -r -g appuser appuser
RUN chown -R appuser:appuser /app
USER appuser

# Set JVM options for container environment
ENV JAVA_OPTS="-Xmx512m -Xms256m -XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0"

# Set Kafka Streams specific JVM options
ENV KAFKA_STREAMS_OPTS="-Dkafka.streams.auto.offset.reset=earliest -Dkafka.streams.processing.guarantee=exactly_once_v2"

# Command to run the application
CMD ["sh", "-c", "java $JAVA_OPTS $KAFKA_STREAMS_OPTS -jar app.jar"]