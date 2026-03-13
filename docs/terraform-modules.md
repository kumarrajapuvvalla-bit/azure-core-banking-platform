# Terraform Modules Reference

**Owner:** Platform Engineering  
**Last Updated:** 2026-03-13  
**Terraform Version:** 1.5.7  
**azurerm Provider:** = 3.85.0 (exact pin)

---

## Module Overview

All infrastructure is managed through purpose-built Terraform modules. The root configuration at `terraform/main.tf` wires all modules together. Modules are kept narrow in scope — each module owns exactly one Azure resource domain.

```
terraform/
├── main.tf                    Root module — all module instantiations
├── variables.tf               Shared input variables
├── outputs.tf                 Cross-module output values
└── modules/
    ├── aks/                   AKS private cluster, node pools, KEDA, WIF
    ├── networking/            VNet, subnets, NSGs, Route Tables, Private DNS
    ├── keyvault/              Key Vault, RBAC, Private Endpoint, seed secrets
    ├── storage/               Storage Accounts, containers, lifecycle, CMK
    ├── acr/                   Azure Container Registry, geo-replication
    └── monitoring/            Log Analytics, Action Groups, metric alerts
```

---

## Module: networking

**Purpose:** Deploys all network infrastructure required by the platform. This is always the first module applied — all other modules depend on networking outputs.

### Resources Created

The module creates a VNet with four dedicated subnets, each with a specific purpose. The AKS subnet hosts all cluster nodes and receives traffic via the Application Gateway. The AGW subnet holds the Azure Application Gateway with WAF Policy. The Private Endpoint subnet provides isolated connectivity to PaaS services without traversing the public internet. The Bastion subnet (optional) enables secure RDP/SSH to private resources.

All NSG rules are defined explicitly in this module. The canonical `DenyAllInbound` rule at priority 4096 means any missing allow rule results in a deny — never an accidental permit. All outbound traffic from AKS nodes is routed through Azure Firewall via a User Defined Route to prevent data exfiltration.

### Key Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `vnet_address_space` | `["10.0.0.0/14"]` | VNet CIDR — sized for 65k nodes |
| `aks_subnet_address_prefix` | `10.0.0.0/16` | AKS node subnet |
| `agw_subnet_address_prefix` | `10.1.0.0/24` | Application Gateway subnet |
| `pe_subnet_address_prefix` | `10.1.1.0/24` | Private Endpoint subnet |
| `firewall_private_ip` | `10.1.3.4` | UDR next-hop for egress |
| `enable_ddos_protection` | `false` | Enabled in prod (PCI-DSS) |

### Usage

```hcl
module "networking" {
  source = "./modules/networking"

  resource_group_name       = azurerm_resource_group.networking.name
  location                  = "uksouth"
  location_short            = "uks"
  environment               = "prod"
  project                   = "pwc-banking"
  tags                      = local.common_tags
  vnet_address_space        = ["10.0.0.0/14"]
  aks_subnet_address_prefix = "10.0.0.0/16"
  agw_subnet_address_prefix = "10.1.0.0/24"
  pe_subnet_address_prefix  = "10.1.1.0/24"
  firewall_private_ip       = "10.1.3.4"
  enable_ddos_protection    = true
}
```

---

## Module: aks

**Purpose:** Deploys a private AKS 1.28 cluster with two node pools, Workload Identity Federation, OPA Gatekeeper policy, and Key Vault CSI integration.

### Key Design Decisions

**Private cluster:** The API server is accessible only via Private Link. This satisfies FCA network segmentation requirements and prevents API server exposure to the public internet. Authorized IP ranges provide additional access control layered on top of private link.

**Exact Kubernetes version pin:** The `kubernetes_version` variable must be set explicitly. Auto-patching is disabled. Version upgrades follow the AKS upgrade runbook (see `docs/runbook-aks-upgrade.md`) to ensure zero transaction downtime via PDB compliance checking.

**Two node pools:** The system pool runs only critical Kubernetes system components (`only_critical_addons_enabled = true`). Application workloads run exclusively on the app node pool, which autoscales independently.

**Maintenance windows:** Node OS upgrades are scheduled for Sunday 02:00–06:00 UTC, inside the ISO 27001 30-day patching window and outside FCA business hours.

### Key Variables

| Variable | Description |
|----------|-------------|
| `kubernetes_version` | AKS cluster version — must match approved version list |
| `system_node_pool_vm_size` | VM SKU for system pool (D4ds_v5 in prod) |
| `app_node_pool_min_count` | Minimum app node count for autoscaler |
| `app_node_pool_max_count` | Maximum app node count for autoscaler |
| `admin_group_object_ids` | Azure AD groups granted cluster-admin via Azure RBAC |

### Usage

```hcl
module "aks" {
  source = "./modules/aks"

  resource_group_name        = azurerm_resource_group.aks.name
  location                   = "uksouth"
  environment                = "prod"
  project                    = "pwc-banking"
  kubernetes_version         = "1.28.5"
  subnet_id                  = module.networking.aks_subnet_id
  log_analytics_workspace_id = module.monitoring.log_analytics_workspace_id
  system_node_pool_vm_size   = "Standard_D4ds_v5"
  system_node_pool_node_count = 3
  app_node_pool_vm_size      = "Standard_D8ds_v5"
  app_node_pool_min_count    = 3
  app_node_pool_max_count    = 20
  key_vault_id               = module.keyvault.key_vault_id
  acr_id                     = module.acr.acr_id
}
```

---

## Module: keyvault

**Purpose:** Deploys Azure Key Vault in RBAC mode with a private endpoint, diagnostic logging, and seed secrets for the platform.

### Key Design Decisions

**RBAC authorization mode:** The module uses `enable_rbac_authorization = true`. Access policies are not used — they cannot be audited through Azure Policy and produce sprawl over time. All access is granted via Azure RBAC role assignments scoped to the vault resource.

**No public access:** `public_network_access_enabled = false`. All access is via Private Endpoint. There is no escape hatch for emergency portal access — this was a deliberate decision after the FCA pen test finding (INC-2024-301) where a vault with public access was discovered.

**Soft-delete and purge protection:** Both are mandatory in production. A 90-day soft-delete retention period satisfies FCA data retention obligations. Purge protection prevents accidental permanent deletion.

**Seed secrets:** The module creates placeholder secrets with 90-day expiry. Real values are injected by the rotation script (`scripts/rotate-secrets.sh`) and never appear in Terraform state.

### Key Variables

| Variable | Description |
|----------|-------------|
| `tenant_id` | Azure AD tenant ID for vault |
| `aks_kubelet_identity_id` | Object ID granted Key Vault Secrets User |
| `platform_admin_group_object_id` | Group granted Key Vault Secrets Officer |
| `soft_delete_retention_days` | 7–90 days (default: 90) |

---

## Module: storage

**Purpose:** Deploys Azure Storage Accounts for Terraform state, audit log archival, and application blob storage.

### Key Design Decisions

**No shared access keys in production:** `shared_access_key_enabled = false`. All access uses managed identity or Workload Identity Federation. Shared access keys cannot be scoped or audited per-principal and are a PCI-DSS risk.

**Customer-managed key encryption (prod only):** When `enable_cmk = true` and `environment = "prod"`, all data is encrypted using a Key Vault-managed key. This satisfies PCI-DSS Requirement 3.4 for protecting stored data.

**Tiered lifecycle management:** Audit logs are automatically moved to Cool tier at 30 days and Archive at 90 days. Deletion occurs at 365 days. This reduced audit log storage costs by approximately 50% after implementation.

**GRS replication in production:** `account_replication_type = "GRS"` ensures data survives a regional Azure outage. UK South primary with UK West secondary.

### Usage Example (Terraform state backend storage)

```hcl
module "tfstate_storage" {
  source = "./modules/storage"

  resource_group_name  = "rg-pwc-banking-tfstate-prod"
  location             = "uksouth"
  environment          = "prod"
  project              = "pwc-banking"
  storage_account_name = "sapwcbankingtfstateprod"
  account_replication_type = "GRS"
  shared_access_key_enabled = false
  enable_private_endpoint  = true
  pe_subnet_id             = module.networking.pe_subnet_id
  prevent_destroy          = true

  containers = [
    { name = "tfstate" }
  ]

  tags = local.common_tags
}
```

---

## Applying Modules

### State management

Each environment maintains its own Terraform state file in a dedicated storage account container:

```
tfstate/
├── prod/platform.tfstate
├── staging/platform.tfstate
└── dev/platform.tfstate
```

State lock is managed via Azure Blob Storage lease mechanism. Concurrent apply operations are prevented.

### Dependency order

The correct apply order is enforced by Terraform's dependency graph, but for first-time deployments the recommended sequence is:

1. Networking module (no dependencies)
2. Storage module (no dependencies)
3. Monitoring module (depends on networking for Private Endpoint)
4. Key Vault module (depends on networking, monitoring)
5. ACR module (depends on networking)
6. AKS module (depends on all above)

### Drift detection

A weekly GitHub Actions scheduled workflow (`terraform-apply.yml` with action=`plan`) runs against production to detect any configuration drift. Drift alerts are sent to the platform engineering email and PagerDuty P2.
