<div align="center">

# 🏦 PwC UK — Enterprise Core Banking Cloud Transformation

[![Azure](https://img.shields.io/badge/Azure-AKS%20%7C%20SQL%20%7C%20Service%20Bus%20%7C%20Key%20Vault-0078D4?style=for-the-badge&logo=microsoft-azure&logoColor=white)](https://azure.microsoft.com)
[![Azure DevOps](https://img.shields.io/badge/Azure%20DevOps-Pipelines%20%7C%20VMSS%20Agents-0078D4?style=for-the-badge&logo=azure-devops&logoColor=white)](https://dev.azure.com)
[![Terraform](https://img.shields.io/badge/Terraform-azurerm%20%7C%20Exact%20Pinning-7B42BC?style=for-the-badge&logo=terraform&logoColor=white)](https://terraform.io)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-Private%20AKS%20%7C%20OPA-326CE5?style=for-the-badge&logo=kubernetes&logoColor=white)](https://kubernetes.io)
[![Compliance](https://img.shields.io/badge/Compliance-FCA%20%7C%20PCI--DSS%20%7C%20ISO%2027001-red?style=for-the-badge)](https://www.fca.org.uk)

**Role:** Azure DevOps Engineer · PwC UK · Full-Time Embedded Engagement
**Duration:** 1 Year 7 Months
**GitHub:** [@kumarrajapuvvalla-bit](https://github.com/kumarrajapuvvalla-bit)

</div>

---

## 📌 About This Repository

Reference implementation rebuilt from 1 year 7 months as an Azure DevOps Engineer at PwC UK,
embedded in an Enterprise Core Banking Cloud Transformation programme. Client: major UK retail bank
migrating from on-premise legacy systems to Microsoft Azure.

Every decision was shaped by **FCA regulatory obligations**, **PCI-DSS**, and **ISO 27001** —
30-day mandatory OS patching, 90-day secret rotation, quarterly pen tests, and Major Incident
reporting thresholds that make every outage carry regulatory weight.

> All code is rebuilt as open-source reference. No PwC methodology, client systems, or
> confidential bank information included.

---

## 🏗️ Platform Architecture

```
┌──────────────────────────────────────────────────────────────────────────┐
│                          Microsoft Azure (UK South)                      │
│                                                                          │
│  ┌─────────────┐    ┌──────────────────────────────────┐                │
│  │ Azure Repos │───▶│  Azure DevOps Pipelines          │                │
│  │   (Git)     │    │  Self-Hosted VMSS Agents (4–40)  │                │
│  └─────────────┘    └──────────────┬───────────────────┘                │
│                                    │                                     │
│                     ┌──────────────▼───────────┐                        │
│                     │       Private ACR         │                        │
│                     └──────────────┬────────────┘                       │
│                                    │                                     │
│              ┌─────────────────────▼──────────────────────┐             │
│              │            Private AKS Cluster              │             │
│              │         (No public API endpoint)            │             │
│              │                                             │             │
│              │  ┌─────────────┐  ┌───────────────────┐   │             │
│              │  │ System Pool  │  │  App Pool          │   │             │
│              │  │ Prometheus   │  │  Core Banking API  │   │             │
│              │  │ Grafana      │  │  Txn Processor     │   │             │
│              │  │ Fluent Bit   │  │  Ledger Service    │   │             │
│              │  └─────────────┘  └───────────────────┘   │             │
│              └─────────────────────────────────────────────┘             │
│                           │                                              │
│          ┌────────────────┼──────────────────────┐                      │
│          ▼                ▼                      ▼                      │
│   Azure SQL          Service Bus            Key Vault                   │
│   (Core Banking      (Async Txns           (WIF — no                    │
│    Ledger)            + DLQ)               secrets)                     │
│                                                                          │
│   ┌─────────────────────────────────────────────────────────────┐       │
│   │    Azure Monitor + Log Analytics + Grafana + PagerDuty      │       │
│   └─────────────────────────────────────────────────────────────┘       │
│   ┌─────────────────────────────────────────────────────────────┐       │
│   │    FCA Major Incident Reporting · PCI-DSS · ISO 27001       │       │
│   └─────────────────────────────────────────────────────────────┘       │
└──────────────────────────────────────────────────────────────────────────┘
```

---

## 🔥 Production Issues Solved

| # | Issue | Category | MTTR | Outcome |
|---|-------|----------|------|---------|
| 1 | azurerm provider auto-upgrade destroys 6 production subnets | Infra | 45 min | Exact pinning — zero recurrence 14 months |
| 2 | Azure Policy silently blocks all AKS deployments across 6 teams | Infra | 2 hrs | Policy Change Protocol — 3 future conflicts caught |
| 3 | Agent pool exhaustion blocking FCA deadline release day | CI/CD | 40 min | Queue time 140min → 12min (91% reduction) |
| 4 | Key Vault secret rotation breaks pipeline mid-release | CI/CD | 15 min | WIF migration — zero auth failures 9 months |
| 5 | AKS node upgrade causes core banking transaction downtime | Kubernetes | 8 min | PDB + OPA — 6 zero-downtime upgrades since |
| 6 | Private AKS API unreachable after NSG quarterly hardening | Kubernetes | 30 min | NSG-in-Terraform — 2 future gaps caught |
| 7 | Blue-green standby exhausts Azure SQL connection pool | Production | 90 sec | Automated standby cleanup — 14 clean releases |
| 8 | 4,847 banking transactions silently DLQ'd for 6 days | Production | 4 hrs | All transactions recovered, schema registry added |
| 9 | Alert fatigue → 40-min missed P0 payment outage | Monitoring | 3 days | Alerts 85/wk → 11/wk, MTTA 22min → 4min |
| 10 | Service Principal with Owner role in FCA pen test | Security | 11 days | Critical finding closed, blast radius -95% |
| 11 | £44,300 wasted on mismatched Azure Reserved Instances | Cost | 1 week | 50% cost reduction, programme 28% under budget |

---

## 🧰 Tech Stack

| Category | Tools |
|----------|-------|
| Cloud | Azure — AKS, ACR, SQL, Service Bus, Key Vault, App Gateway, Monitor |
| IaC | Terraform (azurerm exact pinning), Helm 3 |
| CI/CD | Azure DevOps Pipelines, Self-hosted VMSS agents |
| Auth | Workload Identity Federation (WIF) — zero static SP secrets |
| Containers | Docker (BuildKit), Private AKS 1.28 |
| Monitoring | Azure Monitor, Log Analytics, Grafana, PagerDuty |
| Security | OPA Gatekeeper, Azure Policy, Trivy, Azure Defender |
| Compliance | FCA, PCI-DSS, ISO 27001 |
| Languages | Python 3.11, Bash, PowerShell, YAML, HCL |

---

## 🔐 Compliance Context

| Regulation | How It Shaped Architecture |
|------------|---------------------------|
| **FCA** | 30-min Major Incident threshold shaped monitoring MTTA targets and DR design |
| **PCI-DSS** | Least-privilege RBAC, network segmentation, DLQ monitoring on all payment queues |
| **ISO 27001** | 30-day OS patch window → AKS maintenance windows. 90-day rotation → WIF adoption |

---

## 🏆 Engineering Principles Applied

```
✅  azurerm provider pinned exactly (= x.y.z) — no ~> wildcards ever
✅  ALL NSG rules in Terraform — zero undocumented manual portal rules
✅  Every production Deployment replicas >= 2 — OPA Gatekeeper enforced
✅  Every production Deployment has a PodDisruptionBudget
✅  Workload Identity Federation — no SP secrets to rotate or expire
✅  Custom least-privilege RBAC — no Owner at subscription scope
✅  Blue-green standby scale-down is automated — human step eliminated
✅  DLQ depth monitored on every Service Bus queue
✅  Schema Registry for all async message contracts
✅  Alerts symptom-based (user-facing) not cause-based
```

---

## ⚠️ Disclaimer

Personal portfolio project. All code rebuilt from engineering knowledge as open-source reference.
No proprietary PwC methodology, client data, or confidential bank information included.

---

<div align="center">

**[@kumarrajapuvvalla-bit](https://github.com/kumarrajapuvvalla-bit)**

*If this helped you — ⭐ Star it!*

</div>
