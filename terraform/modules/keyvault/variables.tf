###############################################################
# terraform/modules/keyvault/variables.tf
###############################################################

variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "location_short" { type = string; default = "uks" }
variable "environment" { type = string }
variable "project" { type = string }
variable "tags" { type = map(string) }
variable "tenant_id" { type = string }
variable "aks_kubelet_identity_id" { type = string }
variable "pe_subnet_id" { type = string }
variable "private_dns_zone_id" { type = string }
variable "log_analytics_workspace_id" { type = string }
variable "platform_admin_group_object_id" { type = string; default = "" }
