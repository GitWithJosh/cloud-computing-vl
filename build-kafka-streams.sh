#!/bin/bash

build_kafka_streams() {
    echo "Building Kafka Streams Application"
    echo "================================="
    
    # Check prerequisites
    if ! command -v mvn &> /dev/null; then
        echo "Maven not found. Install with:"
        echo "  Ubuntu/Debian: sudo apt-get install maven"
        echo "  macOS: brew install maven"
        exit 1
    fi
    
    if ! command -v docker &> /dev/null; then
        echo "Docker not found. Please install Docker."
        exit 1
    fi
    
    # Build Java application
    echo "Compiling Java application..."
    cd kafka-streams-app
    mvn clean package -DskipTests
    
    # Build Docker image
    echo "Building Docker image..."
    docker build -t sensor-anomaly-processor:1.0.0 .
    cd ..
    
    # Create uncompressed tar for deployment
    echo "Creating deployment package..."
    docker save sensor-anomaly-processor:1.0.0 -o /tmp/sensor-anomaly-processor.tar
    
    echo "Kafka Streams application built successfully!"
}

# If script is run directly (not sourced), execute the function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    build_kafka_streams
fi