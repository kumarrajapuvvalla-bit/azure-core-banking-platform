###############################################################
# terraform/modules/monitoring/main.tf
# Log Analytics, Action Groups, Alert Rules
# FCA: MTTA <= 4 min for P0 alerts; alert fatigue reduction
###############################################################

resource "azurerm_log_analytics_workspace" "main" {
  name                = "law-${var.project}-${var.environment}-${var.location_short}"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = var.retention_days
  tags                = var.tags
}

resource "azurerm_monitor_action_group" "critical" {
  name                = "ag-${var.project}-critical-${var.environment}"
  resource_group_name = var.resource_group_name
  short_name          = "p0-critical"
  tags                = var.tags

  email_receiver {
    name                    = "platform-engineering"
    email_address           = var.alert_email
    use_common_alert_schema = true
  }

  webhook_receiver {
    name                    = "pagerduty"
    service_uri             = var.pagerduty_webhook
    use_common_alert_schema = true
  }
}

resource "azurerm_monitor_action_group" "warning" {
  name                = "ag-${var.project}-warning-${var.environment}"
  resource_group_name = var.resource_group_name
  short_name          = "p1-warning"
  tags                = var.tags

  email_receiver {
    name                    = "platform-engineering"
    email_address           = var.alert_email
    use_common_alert_schema = true
  }
}

# P0: Payment error rate > 1% (FCA threshold — 30min resolution SLA)
resource "azurerm_monitor_scheduled_query_rules_alert_v2" "payment_error_rate" {
  name                = "alert-payment-error-rate-${var.environment}"
  resource_group_name = var.resource_group_name
  location            = var.location
  description         = "P0: Payment transaction error rate exceeded 1% threshold"
  severity            = 0
  enabled             = true
  tags                = var.tags

  scopes                  = [azurerm_log_analytics_workspace.main.id]
  evaluation_frequency    = "PT2M"
  window_duration         = "PT5M"
  auto_mitigation_enabled = true

  criteria {
    query = <<-QUERY
      ContainerLog
      | where LogEntry has "payment"
      | summarize
          total = count(),
          errors = countif(LogEntry has "ERROR" or LogEntry has "FAILED")
          by bin(TimeGenerated, 2m)
      | where total > 0
      | extend error_rate = (errors * 100.0) / total
      | where error_rate > 1.0
    QUERY

    time_aggregation_method = "Count"
    threshold               = 0
    operator                = "GreaterThan"
  }

  action {
    action_groups = [azurerm_monitor_action_group.critical.id]
  }
}

# P0: Pod availability < 3 pods
resource "azurerm_monitor_metric_alert" "pod_availability" {
  name                = "alert-pod-availability-${var.environment}"
  resource_group_name = var.resource_group_name
  description         = "P0: Banking API pod count below minimum threshold"
  severity            = 0
  enabled             = true
  frequency           = "PT1M"
  window_size         = "PT5M"
  tags                = var.tags

  scopes = [var.aks_cluster_id]

  criteria {
    metric_namespace = "Microsoft.ContainerService/managedClusters"
    metric_name      = "kube_pod_status_ready"
    aggregation      = "Average"
    operator         = "LessThan"
    threshold        = 3
  }

  action {
    action_group_id = azurerm_monitor_action_group.critical.id
  }
}
