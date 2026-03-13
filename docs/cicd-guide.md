# CI/CD Pipeline Guide

**Owner:** Platform Engineering  
**Last Updated:** 2026-03-13

---

## Pipeline Overview

The platform uses five GitHub Actions workflows, each with a specific scope:

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| `build-pipeline.yml` | Push to any branch | Lint, test, validate all services |
| `container-build-push.yml` | Reusable workflow | Build + push a single container image |
| `ci-pipeline.yml` | Push / PR to main | Full CI gate: quality + test + build + scan |
| `cd-pipeline.yml` | CI success on main | Deploy to staging → production |
| `terraform-apply.yml` | Push to terraform/ | Infrastructure plan and apply |
| `security-scan.yml` | Push + scheduled | Trivy, CodeQL, secret detection |
| `secret-rotation.yml` | Monthly schedule | ISO 27001 90-day rotation |

---

## Authentication (Workload Identity Federation)

All pipelines authenticate to Azure using OIDC Workload Identity Federation. No static Service Principal credentials are stored anywhere.

### How it works

```
GitHub Actions OIDC token
       │
       ▼
Azure AD Federated Identity Credential
       │
       ▼  (token exchange)
Azure AD access token (scoped to subscription/resource group)
       │
       ▼
Azure CLI / Terraform / kubectl
```

Each environment (staging, prod) has a separate App Registration with separate federated credentials. Production pipelines require an environment protection rule with required reviewers.

### Required GitHub Secrets

```
AZURE_CLIENT_ID         App Registration client ID (per-env)
AZURE_TENANT_ID         Azure AD tenant ID (shared)
AZURE_SUBSCRIPTION_ID   Target subscription ID (per-env)
ALERT_EMAIL             Platform alert email
PAGERDUTY_WEBHOOK       PagerDuty integration webhook
```

No passwords, client secrets, or SAS tokens are stored in GitHub Secrets.

---

## Build Pipeline (`build-pipeline.yml`)

The build pipeline runs on every push and PR. It is designed to be fast and provide early feedback.

```
Push / PR
    │
    ├─► detect-changes      (path filter — skip unchanged services)
    ├─► code-quality         Ruff, Bandit, Safety, MyPy
    ├─► unit-tests           pytest matrix (3 services × parallel)
    │    └── services: postgres + redis containers
    └─► infra-validate       Terraform fmt + validate + Helm lint
```

The path filter (`dorny/paths-filter`) prevents rebuilding all three services when only one has changed. This reduced average CI duration from 18 minutes to 7 minutes for single-service changes.

---

## Container Build and Push (`container-build-push.yml`)

This is a reusable workflow called by other workflows. It:

1. Logs in to ACR using OIDC (no stored credentials)
2. Generates Docker metadata (tags, labels, OCI annotations)
3. Builds the image with BuildKit and GHA layer cache
4. Generates an SBOM (Software Bill of Materials) in SPDX format
5. Attests build provenance (SLSA Level 2)
6. Runs Trivy vulnerability scan on the pushed image

**BuildKit cache:** Layer caching via GHA cache reduced average image build time from 4m 30s to 1m 45s (61% reduction).

**Image tagging convention:**

| Tag | When | Purpose |
|-----|------|---------|
| `<sha12>` | All builds | Immutable reference for deployment |
| `latest` | Main branch only | Convenience — not used in production manifests |
| `<branch-name>` | All builds | Branch tracking |
| `sha-<short-sha>` | All builds | Readable short ref |

---

## Security Scanning (`security-scan.yml`)

Security scanning runs on every push to main, every PR, and on a Tuesday/Friday 03:00 UTC schedule.

```
security-scan.yml
    │
    ├─► trivy-image-scan     Container image CVE scan (matrix: 3 services)
    │    ├── CRITICAL/HIGH → exit code 1 (blocks main branch)
    │    └── SARIF → GitHub Security Code Scanning
    │
    ├─► trivy-iac-scan        Terraform + K8s + Helm misconfiguration
    │    └── SARIF → GitHub Security Code Scanning
    │
    ├─► codeql-analysis       Semantic Python analysis
    │    └── security-extended queries (SSRF, injection, path traversal)
    │
    ├─► secret-detection      Gitleaks — full git history scan
    │    └── Blocks PR on any credential pattern match
    │
    └─► dependency-review     Blocks PRs introducing high-severity deps
         └── Copyleft licences (GPL-3.0, AGPL-3.0) denied
```

### Trivy severity thresholds

| Context | CRITICAL | HIGH | MEDIUM |
|---------|----------|------|--------|
| main branch push | Block | Block | Report |
| Pull request | Report | Report | Report |
| Scheduled scan | Report | Report | Report |

IaC scanning catches Terraform and Kubernetes misconfigurations (e.g., privileged containers, missing resource limits, insecure network policies) before they reach production.

---

## Terraform Pipeline (`terraform-apply.yml`)

```
terraform-apply.yml
    │
    ├─► terraform init        Remote backend (Azure Blob Storage)
    ├─► terraform validate    Syntax and schema validation
    ├─► terraform plan        Detailed exit code:
    │    ├── exit 0: no changes → skip apply
    │    ├── exit 1: error → fail workflow
    │    └── exit 2: changes → proceed to apply (if action=apply)
    ├─► terraform apply       Auto-approve (gated by environment protection)
    └─► save outputs          tf-outputs.json → artifact (retention: 30d)
```

**Environment protection:** The `prod` GitHub environment requires manual approval from a platform engineering team member before `terraform apply` runs. This prevents unreviewed infrastructure changes in production.

**Drift detection:** The workflow runs weekly in `plan` mode only (no apply) against production. Any plan showing changes triggers a P2 PagerDuty alert. Drift is investigated and reconciled within the sprint.

---

## Deployment Pipeline (`cd-pipeline.yml`)

```
cd-pipeline.yml (triggered after CI success on main)
    │
    ├─► deploy-staging        helm upgrade --atomic --timeout 10m
    │    ├── Wait for rollout
    │    └── Smoke tests (health endpoints only)
    │
    └─► deploy-prod           (requires staging success)
         ├─► Pre-deployment health check (abort if any unhealthy pods)
         ├─► helm upgrade --atomic --timeout 15m --history-max 5
         ├─► Rollout status verification
         ├─► Production smoke tests (read-only)
         └─► Auto-rollback on failure (helm rollback 0)
```

**Atomic deployments:** `--atomic` flag ensures that if a deployment fails (pod crash, readiness probe failure, timeout), Helm automatically rolls back to the previous release. The deployment never leaves the cluster in a partially-upgraded state.

**Blue-green with Helm history:** Keeping 5 releases in history (`--history-max 5`) enables instant rollback to any of the last 5 deployment states. Rollback to the previous release takes approximately 90 seconds.

---

## DORA Metrics

The platform tracks the four DORA engineering metrics, visible in the CI/CD Grafana dashboard:

| Metric | Current | DORA Elite Target |
|--------|---------|------------------|
| Deployment Frequency | Multiple per day | Multiple per day ✅ |
| Lead Time for Changes | ~45 minutes | < 1 hour ✅ |
| Mean Time to Restore | ~8 minutes | < 1 hour ✅ |
| Change Failure Rate | ~3% | < 5% ✅ |

The platform reached DORA Elite classification after introducing atomic deployments, automated rollback, and the smoke test gate between staging and production.
