###############################################################
# terraform/modules/storage/variables.tf
###############################################################

variable "resource_group_name" {
  description = "Resource group for the Storage Account"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "location_short" {
  description = "Short region code for resource naming"
  type        = string
  default     = "uks"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
}

variable "project" {
  description = "Project identifier"
  type        = string
}

variable "tags" {
  description = "Tags applied to storage resources"
  type        = map(string)
  default     = {}
}

variable "storage_account_name" {
  description = "Globally unique storage account name (3-24 chars, alphanumeric)"
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.storage_account_name))
    error_message = "Storage account name must be 3-24 lowercase alphanumeric characters."
  }
}

variable "account_tier" {
  description = "Storage tier: Standard or Premium"
  type        = string
  default     = "Standard"
  validation {
    condition     = contains(["Standard", "Premium"], var.account_tier)
    error_message = "account_tier must be Standard or Premium."
  }
}

variable "account_replication_type" {
  description = "Replication type: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS"
  type        = string
  default     = "GRS"   # Geo-redundant for prod — RTO/RPO compliance
}

variable "shared_access_key_enabled" {
  description = "Enable shared access key authentication — disabled in prod (WIF only)"
  type        = bool
  default     = false
}

variable "blob_soft_delete_retention_days" {
  description = "Days to retain soft-deleted blobs (min 1, max 365)"
  type        = number
  default     = 30
}

variable "container_soft_delete_retention_days" {
  description = "Days to retain soft-deleted containers"
  type        = number
  default     = 30
}

variable "cors_allowed_origins" {
  description = "Origins permitted for CORS requests to blob service"
  type        = list(string)
  default     = []
}

variable "allowed_ip_ranges" {
  description = "IP ranges permitted to access storage without Private Endpoint (non-prod only)"
  type        = list(string)
  default     = []
}

variable "allowed_subnet_ids" {
  description = "Subnet IDs with service endpoint access to storage"
  type        = list(string)
  default     = []
}

variable "containers" {
  description = "List of blob containers to create"
  type = list(object({
    name = string
  }))
  default = []
}

variable "enable_private_endpoint" {
  description = "Deploy a Private Endpoint for the blob service"
  type        = bool
  default     = true
}

variable "pe_subnet_id" {
  description = "Subnet ID for the Storage Private Endpoint"
  type        = string
  default     = ""
}

variable "blob_private_dns_zone_id" {
  description = "Private DNS zone ID for privatelink.blob.core.windows.net"
  type        = string
  default     = ""
}

variable "enable_cmk" {
  description = "Enable customer-managed key encryption (prod only)"
  type        = bool
  default     = false
}

variable "key_vault_id" {
  description = "Key Vault resource ID — required when enable_cmk = true"
  type        = string
  default     = ""
}

variable "cmk_key_name" {
  description = "Key name in Key Vault for CMK storage encryption"
  type        = string
  default     = "storage-cmk"
}

variable "log_analytics_workspace_id" {
  description = "Log Analytics workspace for storage diagnostic logs"
  type        = string
  default     = ""
}

variable "prevent_destroy" {
  description = "Protect the storage account from accidental destruction"
  type        = bool
  default     = true
}
