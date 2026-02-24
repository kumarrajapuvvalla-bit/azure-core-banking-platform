# =============================================================================
# AKS — Private Cluster, Core Banking Platform
# LESSON (Issue #1): Provider pinned EXACTLY. azurerm ~> 3.0 auto-upgraded
# to 3.44.0 which destroyed 6 production subnets. Never use ~> in production.
# LESSON (Issue #4): Workload Identity Federation — no SP secrets to rotate.
# LESSON (Issue #6): Private cluster — agents MUST have NSG rules to reach
# the private endpoint. All NSG rules are in Terraform (networking module).
# =============================================================================

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "= 3.91.0"  # PINNED EXACTLY — never ~>
    }
  }

  backend "azurerm" {
    resource_group_name  = "rg-terraform-state"
    storage_account_name = "stcbterraformstate"
    container_name       = "tfstate"
    key                  = "aks/terraform.tfstate"
    use_azuread_auth     = true
  }
}

provider "azurerm" {
  features {}
}

resource "azurerm_kubernetes_cluster" "main" {
  name                = "${var.project_name}-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  dns_prefix          = "${var.project_name}-${var.environment}"
  kubernetes_version  = var.kubernetes_version

  # Private cluster — no public API endpoint
  # LESSON (Issue #6): NSG must allow TCP/443 from agent subnet to this endpoint
  private_cluster_enabled             = true
  private_cluster_public_fqdn_enabled = false

  network_profile {
    network_plugin = "azure"
    network_policy = "calico"
  }

  # System node pool — monitoring isolated from app workloads
  default_node_pool {
    name                = "system"
    vm_size             = "Standard_D4s_v3"
    vnet_subnet_id      = var.aks_subnet_id
    enable_auto_scaling = true
    min_count           = 2
    max_count           = 5
    node_taints         = ["dedicated=system:NoSchedule"]
    node_labels         = { role = "system" }
  }

  identity {
    type = "SystemAssigned"
  }

  # OIDC + Workload Identity — no SP secrets, no rotation cycle
  # LESSON (Issue #4): SP secret rotation at 2AM broke Saturday morning pipeline
  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  azure_active_directory_role_based_access_control {
    managed            = true
    azure_rbac_enabled = true
  }

  azure_policy_enabled = true

  # Mandatory quarterly OS patches (ISO 27001 / FCA 30-day requirement)
  maintenance_window_node_os {
    frequency   = "Weekly"
    interval    = 1
    duration    = 4
    day_of_week = "Sunday"
    start_time  = "02:00"
    utc_offset  = "+00:00"
  }
}

resource "azurerm_kubernetes_cluster_node_pool" "application" {
  name                  = "application"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.main.id
  vm_size               = "Standard_D8s_v3"
  vnet_subnet_id        = var.aks_subnet_id
  enable_auto_scaling   = true
  min_count             = 3
  max_count             = 15
  node_labels           = { role = "application" }
}

output "cluster_name"     { value = azurerm_kubernetes_cluster.main.name }
output "oidc_issuer_url"  { value = azurerm_kubernetes_cluster.main.oidc_issuer_url }
