###############################################################
# terraform/modules/acr/main.tf
# Azure Container Registry — Premium SKU, private endpoint
###############################################################

resource "azurerm_container_registry" "main" {
  name                = "acr${replace(var.project, "-", "")}${var.environment}"
    resource_group_name = var.resource_group_name
      location            = var.location
        sku                 = var.sku
          admin_enabled       = false # Admin disabled; AKS uses AcrPull RBAC

            public_network_access_enabled = false
              zone_redundancy_enabled       = var.sku == "Premium" ? true : false

                georeplications {
                    location                = "ukwest"
                        zone_redundancy_enabled = false
                            tags                    = var.tags
                              }

                                retention_policy {
                                    days    = 30
                                        enabled = true
                                          }

                                            trust_policy {
                                                enabled = false # Content trust not required for this workload
                                                  }

                                                    tags = var.tags
                                                    }

                                                    resource "azurerm_private_endpoint" "acr" {
                                                      name                = "pe-acr-${var.project}-${var.environment}"
                                                        location            = var.location
                                                          resource_group_name = var.resource_group_name
                                                            subnet_id           = var.pe_subnet_id
                                                              tags                = var.tags

                                                                private_service_connection {
                                                                    name                           = "psc-acr-${var.project}-${var.environment}"
                                                                        private_connection_resource_id = azurerm_container_registry.main.id
                                                                            subresource_names              = ["registry"]
                                                                                is_manual_connection           = false
                                                                                  }

                                                                                    private_dns_zone_group {
                                                                                        name                 = "dns-group-acr"
                                                                                            private_dns_zone_ids = [var.private_dns_zone_id]
                                                                                              }
                                                                                              }
