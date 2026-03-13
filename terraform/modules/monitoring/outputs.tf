###############################################################
# terraform/modules/monitoring/outputs.tf
###############################################################

output "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.id
}

output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.name
}

output "critical_action_group_id" {
  description = "Resource ID of the critical (P0) action group"
  value       = azurerm_monitor_action_group.critical.id
}

output "warning_action_group_id" {
  description = "Resource ID of the warning (P1) action group"
  value       = azurerm_monitor_action_group.warning.id
}
