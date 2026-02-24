# =============================================================================
# NSG — All Rules as Code
#
# LESSON (Issue #6): Bank's network team did quarterly hardening manually.
# They removed a broad Allow rule and replaced with specific rules — but
# MISSED adding TCP/443 from agent subnet to AKS private endpoint subnet.
# Result: ALL pipelines across ALL 8 workstreams failed.
# An FCA compliance patch was blocked on a Friday afternoon.
#
# THE FIX: Every single NSG rule is now in this file.
# Any change = a PR = reviewed = tracked in git forever.
# The "missed rule" that only existed in someone's head now has a comment
# explaining exactly why it must never be removed.
# =============================================================================

resource "azurerm_network_security_group" "devops_agents" {
  name                = "nsg-devops-agents-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
}

# ─── THE RULE THAT WAS MISSING IN THE MONTH 12 INCIDENT ───────────────────
# TCP/443 from agent subnet to AKS private endpoint subnet.
# Without this rule: kubectl times out, all deployments fail.
# DO NOT REMOVE. DO NOT "SIMPLIFY" WITH A BROADER RULE THAT MIGHT GET DELETED.
resource "azurerm_network_security_rule" "agents_to_aks_api" {
  name                        = "Allow-Agents-to-AKS-PrivateEndpoint-443"
  priority                    = 100
  direction                   = "Outbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "443"
  source_address_prefix       = var.agent_subnet_cidr
  destination_address_prefix  = var.aks_private_endpoint_subnet_cidr
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.devops_agents.name
  description                 = "CRITICAL: Agents reach AKS private API. Missing = all pipelines fail. Added after Month 12 incident."
}

resource "azurerm_network_security_rule" "agents_to_acr" {
  name                        = "Allow-Agents-to-ACR-443"
  priority                    = 110
  direction                   = "Outbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "443"
  source_address_prefix       = var.agent_subnet_cidr
  destination_address_prefix  = "AzureContainerRegistry"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.devops_agents.name
}

resource "azurerm_network_security_rule" "agents_to_keyvault" {
  name                        = "Allow-Agents-to-KeyVault-443"
  priority                    = 120
  direction                   = "Outbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "443"
  source_address_prefix       = var.agent_subnet_cidr
  destination_address_prefix  = "AzureKeyVault"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.devops_agents.name
}

resource "azurerm_network_security_rule" "agents_deny_all_outbound" {
  name                        = "Deny-All-Other-Outbound"
  priority                    = 4096
  direction                   = "Outbound"
  access                      = "Deny"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.devops_agents.name
}

resource "azurerm_subnet_network_security_group_association" "devops_agents" {
  subnet_id                 = var.agent_subnet_id
  network_security_group_id = azurerm_network_security_group.devops_agents.id
}

output "agent_nsg_id" { value = azurerm_network_security_group.devops_agents.id }
