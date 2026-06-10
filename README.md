# openstack-kubernetes-cluster

Immutable cloud infrastructure on OpenStack — multi-node K3s cluster with zero-downtime deployments, autoscaling, and a full big data stack.

![Terraform](https://img.shields.io/badge/Terraform-7B42BC?style=flat-square&logo=terraform&logoColor=white)
![Kubernetes](https://img.shields.io/badge/Kubernetes-326CE5?style=flat-square&logo=kubernetes&logoColor=white)
![OpenStack](https://img.shields.io/badge/OpenStack-ED1944?style=flat-square&logo=openstack&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-2496ED?style=flat-square&logo=docker&logoColor=white)
![Apache Kafka](https://img.shields.io/badge/Apache_Kafka-231F20?style=flat-square&logo=apachekafka&logoColor=white)
![Apache Spark](https://img.shields.io/badge/Apache_Spark-E25A1C?style=flat-square&logo=apachespark&logoColor=white)

## Overview

The entire infrastructure is defined in Terraform and provisioned on OpenStack via cloud-init — no manual node setup. A K3s master and two worker nodes form the cluster, fronted by a Traefik ingress controller. Terraform workspaces drive a blue-green deployment strategy with automatic health checks and rollback, giving true zero-downtime upgrades. On top of this foundation sit a Streamlit application, a Prometheus/Grafana monitoring stack, a MinIO data lake, and an Apache Kafka + Spark stream processing pipeline.

## Architecture

```
OpenStack
├── K3s Master    — control plane, Prometheus, Grafana
├── K3s Worker 1  — application pods, HPA
├── K3s Worker 2  — application pods, HPA
└── Ingress       — Traefik, port 80

Deployment strategy: Terraform Workspaces (blue/green)
  → parallel infrastructure build → health check → traffic switch → auto-rollback on failure
```

| Component | Technology | Role |
|---|---|---|
| Infrastructure as Code | Terraform | Immutable provisioning, workspace-based blue/green |
| Container Orchestration | Kubernetes (K3s) | Multi-node cluster, HPA, rolling updates |
| Ingress | Traefik | Load balancing, service discovery |
| Cloud Platform | OpenStack | Compute, networking, storage |
| Monitoring | Prometheus + Grafana | HPA metrics, scaling dashboards |
| Data Lake | MinIO | S3-compatible object storage |
| Batch Processing | Apache Spark + MLlib | Distributed ML pipelines |
| Stream Processing | Apache Kafka | Real-time event streaming, ML integration |
| Application | Streamlit + Google Gemini API | AI-powered calorie estimation from food images |

## Quick Start

### Prerequisites

- OpenStack access with admin rights
- Terraform ≥ 1.0
- SSH key registered in OpenStack

### Deploy

```bash
git clone <repo-url> && cd openstack-kubernetes-cluster
chmod +x setup.sh && ./setup.sh

# Configure credentials
cp openrc.sh.template openrc.sh && vim openrc.sh
cp terraform.tfvars.template terraform.tfvars && vim terraform.tfvars

# Deploy
source openrc.sh
./version-manager.sh deploy v1.0
```

### Key Commands

```bash
./version-manager.sh zero-downtime v1.1   # Zero-downtime upgrade
./version-manager.sh rollback v1.0        # Rollback to previous version
./version-manager.sh scale 5              # Scale to N replicas
./version-manager.sh status               # Cluster health check
./monitor.sh                              # Live monitoring
./scaling-demo.sh                         # Automated HPA demo
```

### Endpoints (after deploy)

| Service | URL |
|---|---|
| Application | `http://MASTER-IP/` (Ingress) or `:30001` (NodePort) |
| Grafana | `http://MASTER-IP:30300` (admin/admin) |
| Prometheus | `http://MASTER-IP:30090` |
| MinIO | `http://MASTER-IP:30901` |
| Kafka UI | `http://MASTER-IP:30902` |

## Project Structure

```
openstack-kubernetes-cluster/
├── main.tf                        # Terraform infrastructure definition
├── variables.tf
├── cloud-init-master.tpl          # Master node bootstrap
├── cloud-init-worker.tpl          # Worker node bootstrap
├── version-manager.sh             # Deployment, scaling, rollback
├── monitor.sh                     # Live cluster monitoring
├── scaling-demo.sh                # Automated HPA demonstration
├── app/
│   ├── caloguessr.py              # Streamlit application
│   ├── Dockerfile
│   └── k8s-deployment.yaml
├── big-data/
│   ├── datalake.yaml              # MinIO setup
│   ├── spark-ml-pipeline-job.yaml
│   ├── kafka-cluster.yaml
│   └── kafka-streams-deployment.yaml
└── grafana-dashboard-caloguessr.json
```
