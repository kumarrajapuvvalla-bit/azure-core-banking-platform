###############################################################
# terraform/modules/keyvault/outputs.tf
###############################################################

output "key_vault_id" {
  description = "Resource ID of the Azure Key Vault"
  value       = azurerm_key_vault.main.id
}

output "key_vault_name" {
  description = "Name of the Azure Key Vault"
  value       = azurerm_key_vault.main.name
}

output "vault_uri" {
  description = "URI for accessing the Key Vault (used by CSI driver and app config)"
  value       = azurerm_key_vault.main.vault_uri
  sensitive   = true
}

output "private_endpoint_ip" {
  description = "Private IP address of the Key Vault private endpoint"
  value       = azurerm_private_endpoint.keyvault.private_service_connection[0].private_ip_address
}

output "private_endpoint_id" {
  description = "Resource ID of the Key Vault private endpoint"
  value       = azurerm_private_endpoint.keyvault.id
}
