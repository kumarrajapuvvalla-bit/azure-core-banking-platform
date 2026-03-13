# PwC UK — Enterprise Core Banking Cloud Transformation

[![CI Pipeline](https://github.com/kumarrajapuvvalla-bit/pwc-azure-banking-devops/actions/workflows/ci-pipeline.yml/badge.svg)](https://github.com/kumarrajapuvvalla-bit/pwc-azure-banking-devops/actions/workflows/ci-pipeline.yml)
[![Terraform](https://img.shields.io/badge/Terraform-1.5.7-623CE4?logo=terraform)](https://terraform.io)
[![AKS](https://img.shields.io/badge/AKS-1.28-326CE5?logo=kubernetes)](https://azure.microsoft.com/en-gb/products/kubernetes-service)
[![Compliance](https://img.shields.io/badge/Compliance-FCA%20%7C%20PCI--DSS%20%7C%20ISO27001-red)](https://www.fca.org.uk)

> **Role:** Azure DevOps Engineer · PwC UK · Full-Time Embedded Engagement (1 Year 7 Months)  
> **Domain:** UK Major Retail Bank — Core Banking Cloud Transformation  
> **Disclaimer:** Personal portfolio project. All code rebuilt from engineering knowledge as open-source reference. No PwC methodology, client IP, or confidential banking data included.

---

## Project Overview

This repository is a reference implementation of the Azure DevOps platform I built and operated during a 1-year 7-month embedded engagement at PwC UK, supporting a major UK retail bank migrating from on-premise legacy systems to Microsoft Azure.

The platform supports a core banking workload processing financial transactions at scale, subject to FCA Major Incident thresholds (30-minute resolution), PCI-DSS network segmentation requirements, and ISO 27001 30-day OS patching windows.

Every architecture decision in this repository reflects real production constraints. The NSG rules, provider pin versions, PDB configurations, and WIF authentication patterns all exist because of real incidents encountered and resolved during the engagement.

---

## Architecture

The platform is deployed in Azure UK South with availability zone redundancy across all critical components.

```
                           ┌─────────────────────────────────────────────┐
                           │         Microsoft Azure (UK South)           │
                           │                                               │
   HTTPS (TLS 1.2+)       │  ┌─────────────┐     ┌───────────────────┐  │
   ─────────────────────▶  │  │ App Gateway │────▶│  Private AKS 1.28 │  │
                           │  │ + WAF Policy│     │  (3 AZs, PDB, OPA)│  │
                           │  └─────────────┘     └───────────────────┘  │
                           │                               │               │
                           │           Private Endpoints   │               │
                           │  ┌─────────────┐  ┌──────────────────────┐  │
                           │  │  Key Vault  │  │  Azure Container     │  │
                           │  │  (CSI+WIF)  │  │  Registry (Premium)  │  │
                           │  └─────────────┘  └──────────────────────┘  │
                           │                                               │
                           │  ┌─────────────┐  ┌──────────────────────┐  │
                           │  │ Azure SQL   │  │  Azure Service Bus   │  │
                           │  │ (Geo-HA)    │  │  (DLQ Monitored)     │  │
                           │  └─────────────┘  └──────────────────────┘  │
                           │                                               │
                           │  ┌─────────────────────────────────────────┐ │
                           │  │  Log Analytics → Grafana → PagerDuty    │ │
                           │  └─────────────────────────────────────────┘ │
                           └─────────────────────────────────────────────┘
```

For detailed architecture documentation, see [docs/architecture.md](docs/architecture.md).

---

## Tools and Technologies

| Category | Technology |
|----------|-----------|
| Cloud | Azure — AKS, ACR, Key Vault, SQL, Service Bus, App Gateway, Monitor |
| Infrastructure as Code | Terraform 1.5.x (azurerm exact pinning), Helm 3 |
| CI/CD | GitHub Actions (this repo), Azure DevOps Pipelines (engagement) |
| Authentication | Workload Identity Federation (OIDC) — zero static SP secrets |
| Containers | Docker BuildKit, Private AKS 1.28, OPA Gatekeeper |
| Monitoring | Azure Monitor, Log Analytics, Prometheus, Grafana, PagerDuty |
| Security | OPA Gatekeeper, Azure Policy, Trivy, Microsoft Defender for Containers |
| Compliance | FCA, PCI-DSS, ISO 27001 |
| Languages | Python 3.11, Bash, HCL, YAML |

---

## Infrastructure Design

### Terraform Module Structure

```
terraform/
├── main.tf                    # Root configuration — all modules wired here
├── variables.tf               # Input variables with validation
├── outputs.tf                 # Outputs for downstream modules/pipelines
└── modules/
    ├── aks/                   # AKS private cluster, node pools, WIF, OPA
    ├── networking/            # VNet, NSGs, Route Tables, Private DNS zones
    ├── keyvault/              # Key Vault, RBAC, Private Endpoint
    ├── acr/                   # Azure Container Registry, Private Endpoint
    └── monitoring/            # Log Analytics, Action Groups, Alert Rules
```

**Key design decisions:**

All `azurerm` provider versions are pinned with exact constraint (`= x.y.z`). Following an incident where `~> 3.0` caused an auto-upgrade that destroyed 6 production subnets during a plan/apply cycle, the project standard is exact pinning with deliberate version bump PRs.

All NSG rules are defined in Terraform with explicit `DenyAllInbound` at priority 4096. No NSG rules are created via the Azure portal. This was enforced after an incident where quarterly NSG hardening broke private AKS API reachability because a portal-created rule was not reflected in state.

---

## CI/CD Pipeline

```
Push / PR
    │
    ▼
┌─────────────────────────────────────────────────────────┐
│ lint-and-validate                                        │
│  • Ruff (Python lint) + Bandit (security) + Safety      │
│  • Terraform fmt -check + validate                      │
│  • Helm lint (default + prod values)                    │
└─────────────────────────┬───────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────┐
│ unit-tests                                               │
│  • pytest with coverage >= 80%                          │
│  • PostgreSQL service container                         │
└─────────────────────────┬───────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────┐
│ build-and-scan                                           │
│  • Docker BuildKit with layer cache (GHA)               │
│  • Trivy scan — exit code 1 on CRITICAL/HIGH            │
│  • Image pushed to ACR with SHA tag                     │
└─────────────────────────┬───────────────────────────────┘
                          │ (main branch only)
                          ▼
┌──────────────┐    ┌──────────────┐    ┌──────────────────┐
│  Staging     │───▶│  Smoke Tests │───▶│  Production      │
│  Helm Deploy │    │  (health)    │    │  Helm Deploy     │
│  --atomic    │    └──────────────┘    │  + Verification  │
└──────────────┘                        └──────────────────┘
```

Authentication throughout uses OIDC Workload Identity Federation — no static Service Principal secrets are stored in GitHub Secrets. Azure RBAC is used at the subscription level for all pipeline identities.

---

## Deployment Instructions

### Prerequisites

- Azure CLI >= 2.54.0
- Terraform >= 1.5.0
- kubectl >= 1.28.0
- Helm >= 3.13.0

### Initial Setup

1. Configure Azure credentials and Workload Identity Federation:
```bash
# Set your subscription
az account set --subscription "<YOUR_SUBSCRIPTION_ID>"

# Create Terraform state storage
az group create --name rg-pwc-banking-tfstate-prod --location uksouth
az storage account create \
  --name sapwcbankingtfstateprod \
  --resource-group rg-pwc-banking-tfstate-prod \
  --sku Standard_GRS \
  --min-tls-version TLS1_2
az storage container create \
  --name tfstate \
  --account-name sapwcbankingtfstateprod
```

2. Deploy infrastructure:
```bash
cd terraform
terraform init
terraform plan -var="environment=staging" -out=tfplan
terraform apply tfplan
```

3. Configure kubectl:
```bash
az aks get-credentials \
  --resource-group rg-pwc-banking-aks-staging-uks \
  --name aks-pwc-banking-staging-uks \
  --admin
```

4. Deploy application via Helm:
```bash
./scripts/deploy.sh staging <IMAGE_TAG>
```

---

## Monitoring and Observability

### Alert Hierarchy

| Priority | Alert | Threshold | MTTA Target |
|----------|-------|-----------|-------------|
| P0 | Payment error rate | > 1% over 2m | 4 minutes |
| P0 | API P99 latency | > 3s over 5m | 4 minutes |
| P0 | Pod availability | < 3 pods available | 4 minutes |
| P1 | DLQ accumulation | > 10 messages over 10m | 15 minutes |
| P1 | Memory pressure | > 85% limit over 5m | 15 minutes |
| P2 | TLS cert expiry | < 30 days | 4 hours |

Alerts route through Prometheus Alertmanager → PagerDuty. The alert configuration reduced weekly alert volume from 85 to 11 (87% reduction) and improved MTTA from 22 minutes to 4 minutes, meeting FCA P0 reporting thresholds.

### Grafana Dashboards

Dashboards are stored as JSON in `monitoring/grafana/dashboards/` and provisioned automatically via ConfigMap in the monitoring namespace.

- **Banking API Overview** — SLA tracking, P99 latency, payment error rate, pod availability
- **Infrastructure Overview** — Node resource utilization, cluster capacity, AKS events
- **Security Overview** — OPA policy violations, failed authentication, Key Vault access audit

---

## Security Practices

**Authentication:** All pipeline and workload authentication uses Workload Identity Federation. No static Service Principal secrets. This was adopted after an incident where a Service Principal with Owner-level RBAC was discovered during an FCA penetration test.

**Container Security:** All containers run as non-root (UID 10001), with read-only root filesystems and all Linux capabilities dropped. Seccomp profile RuntimeDefault is enforced cluster-wide via OPA Gatekeeper.

**Secret Management:** Azure Key Vault with RBAC authorization. Secrets mounted via CSI Secrets Store driver with 2-minute rotation sync. No plaintext credentials in Kubernetes Secrets, environment variables, or container images.

**Network Security:** Private AKS API endpoint with authorized IP ranges. All PaaS services accessed via Private Endpoints. Azure Firewall with UDR for all egress. NSG rules deny-all-inbound by default with explicit allow rules only.

**Compliance:** 30-day OS patching via AKS maintenance windows (ISO 27001 A.12.6.1). 90-day secret rotation enforced via automated GitHub Actions schedule. Quarterly Terraform drift detection via CI pipeline.

---

## Repository Structure

```
.
├── .github/
│   └── workflows/
│       ├── ci-pipeline.yml        # Build, lint, test, scan
│       ├── cd-pipeline.yml        # Deploy to staging → prod
│       └── terraform-apply.yml    # Infrastructure provisioning
├── terraform/
│   ├── main.tf                    # Root configuration
│   ├── variables.tf               # Input variables
│   ├── outputs.tf                 # Outputs
│   └── modules/
│       ├── aks/                   # AKS module
│       ├── networking/            # Network module
│       ├── keyvault/              # Key Vault module
│       ├── acr/                   # Container Registry module
│       └── monitoring/            # Monitoring module
├── kubernetes/
│   ├── deployments/               # Deployment manifests
│   └── services/                  # Service and Ingress manifests
├── helm/
│   └── banking-api/               # Application Helm chart
│       ├── Chart.yaml
│       ├── values.yaml            # Default values
│       └── values-prod.yaml       # Production overrides
├── monitoring/
│   ├── prometheus/                # PrometheusRule, ServiceMonitor
│   └── grafana/
│       └── dashboards/            # Grafana dashboard JSON
├── scripts/
│   ├── deploy.sh                  # Helm deployment script
│   └── rotate-secrets.sh          # ISO 27001 secret rotation
└── docs/
    ├── architecture.md            # Platform architecture
    └── runbook-aks-upgrade.md     # AKS upgrade runbook
```

---

## Production Issues Solved

| Issue | Category | MTTR | Outcome |
|-------|----------|------|---------|
| azurerm provider auto-upgrade destroys 6 production subnets | Infra | 45 min | Exact pinning — zero recurrence 14 months |
| Azure Policy silently blocks all AKS deployments | Infra | 2 hrs | Policy Change Protocol — 3 future conflicts caught |
| Agent pool exhaustion blocking FCA deadline release | CI/CD | 40 min | Queue time 140min → 12min (91% reduction) |
| Key Vault secret rotation breaks pipeline mid-release | CI/CD | 15 min | WIF migration — zero auth failures 9 months |
| AKS node upgrade causes transaction downtime | Kubernetes | 8 min | PDB + OPA — 6 zero-downtime upgrades since |
| Private AKS API unreachable after NSG hardening | Kubernetes | 30 min | NSG-in-Terraform — 2 future gaps caught |
| Blue-green standby exhausts Azure SQL connection pool | Production | 90 sec | Automated standby cleanup — 14 clean releases |
| 4,847 banking transactions silently DLQ'd for 6 days | Production | 4 hrs | All transactions recovered, schema registry added |
| Alert fatigue causes 40-min missed P0 payment outage | Monitoring | 3 days | Alerts 85/wk → 11/wk, MTTA 22min → 4min |
| Service Principal with Owner role found in FCA pen test | Security | 11 days | Critical finding closed, blast radius -95% |
| £44,300 wasted on mismatched Azure Reserved Instances | Cost | 1 week | 50% cost reduction, programme 28% under budget |

---

*If this helped you — ⭐ Star it and connect: [@kumarrajapuvvalla-bit](https://github.com/kumarrajapuvvalla-bit)*
