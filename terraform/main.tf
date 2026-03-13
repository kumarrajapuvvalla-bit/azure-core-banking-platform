###############################################################
# terraform/main.tf
# Root Terraform configuration for PwC Azure Banking Platform
###############################################################

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "= 3.85.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "= 2.47.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "= 2.24.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "= 2.12.1"
    }
    random = {
      source  = "hashicorp/random"
      version = "= 3.6.0"
    }
  }

  backend "azurerm" {
    resource_group_name  = "rg-pwc-banking-tfstate-prod"
    storage_account_name = "sapwcbankingtfstateprod"
    container_name       = "tfstate"
    key                  = "prod/platform.tfstate"
    use_oidc             = true
  }
}

provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy    = false
      recover_soft_deleted_key_vaults = true
    }
    resource_group {
      prevent_deletion_if_contains_resources = true
    }
  }
  use_oidc = true
}

provider "azuread" {
  use_oidc = true
}

locals {
  environment    = var.environment
  location       = var.location
  location_short = var.location_short
  project        = "pwc-banking"

  common_tags = {
    Environment    = var.environment
    Project        = "UK Core Banking Transformation"
    ManagedBy      = "Terraform"
    Owner          = "platform-engineering@pwc.com"
    CostCentre     = var.cost_centre
    Compliance     = "FCA:PCI-DSS:ISO27001"
    DataClass      = "Restricted"
  }

  node_pool_config = {
    prod = {
      system_vm_size = "Standard_D4ds_v5"
      system_count   = 3
      app_min        = 3
      app_max        = 20
      app_vm_size    = "Standard_D8ds_v5"
    }
    staging = {
      system_vm_size = "Standard_D2ds_v5"
      system_count   = 2
      app_min        = 2
      app_max        = 8
      app_vm_size    = "Standard_D4ds_v5"
    }
    dev = {
      system_vm_size = "Standard_D2ds_v5"
      system_count   = 1
      app_min        = 1
      app_max        = 4
      app_vm_size    = "Standard_D2ds_v5"
    }
  }
}

resource "azurerm_resource_group" "platform" {
  name     = "rg-${local.project}-platform-${local.environment}-${local.location_short}"
  location = local.location
  tags     = local.common_tags

  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_resource_group" "aks" {
  name     = "rg-${local.project}-aks-${local.environment}-${local.location_short}"
  location = local.location
  tags     = local.common_tags
}

resource "azurerm_resource_group" "networking" {
  name     = "rg-${local.project}-networking-${local.environment}-${local.location_short}"
  location = local.location
  tags     = local.common_tags
}

resource "azurerm_resource_group" "monitoring" {
  name     = "rg-${local.project}-monitoring-${local.environment}-${local.location_short}"
  location = local.location
  tags     = local.common_tags
}

module "networking" {
  source = "./modules/networking"

  resource_group_name       = azurerm_resource_group.networking.name
  location                  = local.location
  environment               = local.environment
  project                   = local.project
  tags                      = local.common_tags
  vnet_address_space        = var.vnet_address_space
  aks_subnet_address_prefix = var.aks_subnet_address_prefix
  agw_subnet_address_prefix = var.agw_subnet_address_prefix
  pe_subnet_address_prefix  = var.pe_subnet_address_prefix
}

module "aks" {
  source = "./modules/aks"

  resource_group_name        = azurerm_resource_group.aks.name
  location                   = local.location
  environment                = local.environment
  project                    = local.project
  tags                       = local.common_tags
  kubernetes_version         = var.kubernetes_version
  subnet_id                  = module.networking.aks_subnet_id
  log_analytics_workspace_id = module.monitoring.log_analytics_workspace_id
  system_node_pool_vm_size   = local.node_pool_config[local.environment].system_vm_size
  system_node_pool_node_count = local.node_pool_config[local.environment].system_count
  app_node_pool_vm_size      = local.node_pool_config[local.environment].app_vm_size
  app_node_pool_min_count    = local.node_pool_config[local.environment].app_min
  app_node_pool_max_count    = local.node_pool_config[local.environment].app_max
  key_vault_id               = module.keyvault.key_vault_id
  acr_id                     = module.acr.acr_id
}

module "keyvault" {
  source = "./modules/keyvault"

  resource_group_name      = azurerm_resource_group.platform.name
  location                 = local.location
  environment              = local.environment
  project                  = local.project
  tags                     = local.common_tags
  tenant_id                = data.azurerm_client_config.current.tenant_id
  aks_kubelet_identity_id  = module.aks.kubelet_identity_object_id
  pe_subnet_id             = module.networking.pe_subnet_id
  private_dns_zone_id      = module.networking.keyvault_private_dns_zone_id
}

module "acr" {
  source = "./modules/acr"

  resource_group_name = azurerm_resource_group.platform.name
  location            = local.location
  environment         = local.environment
  project             = local.project
  tags                = local.common_tags
  sku                 = var.environment == "prod" ? "Premium" : "Standard"
  pe_subnet_id        = module.networking.pe_subnet_id
  private_dns_zone_id = module.networking.acr_private_dns_zone_id
}

module "monitoring" {
  source = "./modules/monitoring"

  resource_group_name = azurerm_resource_group.monitoring.name
  location            = local.location
  environment         = local.environment
  project             = local.project
  tags                = local.common_tags
  retention_days      = var.environment == "prod" ? 90 : 30
  alert_email         = var.alert_email
  pagerduty_webhook   = var.pagerduty_webhook
}

data "azurerm_client_config" "current" {}
data "azurerm_subscription" "current" {}
