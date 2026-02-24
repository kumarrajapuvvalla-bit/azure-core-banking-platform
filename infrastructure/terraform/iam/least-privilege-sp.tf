# =============================================================================
# IAM — Least-Privilege Terraform Service Principal
#
# LESSON (Issue #10): FCA annual pen test found Terraform SP had Owner role
# on the ENTIRE production subscription. Owner = full control including
# role assignment. If leaked: attacker owns the bank's Azure subscription.
# Set in Month 1 as "temporary" to unblock the team. Never tightened.
#
# FIX: Custom RBAC role with ONLY the permissions Terraform actually uses,
# identified from 6 months of Azure Activity Log analysis.
# =============================================================================

data "azurerm_subscription" "current" {}
data "azurerm_client_config" "current" {}

resource "azurerm_role_definition" "terraform_deployer" {
  name        = "terraform-infrastructure-deployer"
  scope       = data.azurerm_subscription.current.id
  description = "Least-privilege Terraform role. Replaces Owner (FCA pen test Critical finding Month 13)."

  permissions {
    actions = [
      "Microsoft.Resources/resourceGroups/read",
      "Microsoft.Resources/resourceGroups/write",
      "Microsoft.ContainerService/managedClusters/read",
      "Microsoft.ContainerService/managedClusters/write",
      "Microsoft.ContainerService/managedClusters/agentPools/read",
      "Microsoft.ContainerService/managedClusters/agentPools/write",
      "Microsoft.Network/virtualNetworks/subnets/read",
      "Microsoft.Network/networkSecurityGroups/read",
      "Microsoft.Network/networkSecurityGroups/write",
      "Microsoft.Network/networkSecurityGroups/securityRules/read",
      "Microsoft.Network/networkSecurityGroups/securityRules/write",
      "Microsoft.Network/networkSecurityGroups/securityRules/delete",
      "Microsoft.ContainerRegistry/registries/read",
      "Microsoft.ContainerRegistry/registries/write",
      "Microsoft.Sql/servers/read",
      "Microsoft.Sql/servers/write",
      "Microsoft.Sql/servers/databases/read",
      "Microsoft.Sql/servers/databases/write",
      "Microsoft.ServiceBus/namespaces/read",
      "Microsoft.ServiceBus/namespaces/write",
      "Microsoft.KeyVault/vaults/read",
      "Microsoft.KeyVault/vaults/write",
      "Microsoft.Insights/diagnosticSettings/read",
      "Microsoft.Insights/diagnosticSettings/write",
      "Microsoft.Insights/metricAlerts/read",
      "Microsoft.Insights/metricAlerts/write",
    ]
    not_actions = [
      # EXPLICITLY EXCLUDED — this was the main Owner risk
      "Microsoft.Authorization/*/write",   # Cannot assign roles
      "Microsoft.Authorization/*/delete",
    ]
  }

  # Scoped to specific resource groups — NOT subscription root
  assignable_scopes = [
    "${data.azurerm_subscription.current.id}/resourceGroups/rg-corebanking-prod",
    "${data.azurerm_subscription.current.id}/resourceGroups/rg-corebanking-staging",
  ]
}

output "custom_role_id" { value = azurerm_role_definition.terraform_deployer.role_definition_resource_id }
