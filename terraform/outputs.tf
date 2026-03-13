###############################################################
# terraform/outputs.tf
# Outputs for PwC Azure Banking Platform
###############################################################

output "aks_cluster_name" {
  description = "Name of the AKS cluster"
  value       = module.aks.cluster_name
}

output "aks_cluster_id" {
  description = "Resource ID of the AKS cluster"
  value       = module.aks.cluster_id
}

output "aks_oidc_issuer_url" {
  description = "OIDC issuer URL for Workload Identity Federation"
  value       = module.aks.oidc_issuer_url
}

output "acr_login_server" {
  description = "Login server hostname for Azure Container Registry"
  value       = module.acr.login_server
}

output "key_vault_uri" {
  description = "URI of the Azure Key Vault"
  value       = module.keyvault.vault_uri
  sensitive   = true
}

output "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics workspace"
  value       = module.monitoring.log_analytics_workspace_id
}

output "vnet_id" {
  description = "Resource ID of the platform VNet"
  value       = module.networking.vnet_id
}

output "aks_subnet_id" {
  description = "Resource ID of the AKS node subnet"
  value       = module.networking.aks_subnet_id
}

output "resource_group_platform" {
  description = "Name of the platform resource group"
  value       = azurerm_resource_group.platform.name
}

output "resource_group_aks" {
  description = "Name of the AKS resource group"
  value       = azurerm_resource_group.aks.name
}
