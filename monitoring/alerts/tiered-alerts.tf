# =============================================================================
# Azure Monitor Alerts — Tiered Severity Model
#
# LESSON (Issue #9): 340 alerts, 85/week, 82% informational noise.
# On-call bulk-acknowledged 12 alerts Saturday night.
# One was payment error rate 34% — a real P0.
# Missed for 40 minutes. Discovered when customers emailed support.
#
# FIX:
#   - Deleted 198 alerts (kept symptom-based, user-facing, actionable only)
#   - 3-tier model: P0 / P1 / P2
#   - P0 = user-facing symptoms ONLY
#   - 5-minute window on all alerts (eliminates transient spike noise)
#   - Result: 85/week → 11/week, MTTA 22min → 4min
# =============================================================================

# P0 action group — page on-call + backup + engineering manager
resource "azurerm_monitor_action_group" "p0_critical" {
  name                = "ag-p0-critical-corebanking"
  resource_group_name = var.resource_group_name
  short_name          = "P0-Critical"

  email_receiver {
    name          = "oncall-engineer"
    email_address = var.oncall_email
  }
  email_receiver {
    name          = "engineering-manager"
    email_address = var.eng_manager_email
  }
  webhook_receiver {
    name        = "pagerduty-p0"
    service_uri = var.pagerduty_p0_webhook
  }
}

resource "azurerm_monitor_action_group" "p1_high" {
  name                = "ag-p1-high-corebanking"
  resource_group_name = var.resource_group_name
  short_name          = "P1-High"
  webhook_receiver {
    name        = "pagerduty-p1"
    service_uri = var.pagerduty_p1_webhook
  }
}

resource "azurerm_monitor_action_group" "p2_slack" {
  name                = "ag-p2-slack-corebanking"
  resource_group_name = var.resource_group_name
  short_name          = "P2-Slack"
  webhook_receiver {
    name        = "slack-ops"
    service_uri = var.slack_webhook_url
  }
}

# P0: Payment API error rate > 1% for 5 minutes
resource "azurerm_monitor_metric_alert" "payment_error_rate_p0" {
  name                = "P0-PaymentService-ErrorRate-GT-1pct"
  resource_group_name = var.resource_group_name
  scopes              = [var.app_insights_id]
  description         = "P0: Payment errors reaching users. FCA reportable if sustained."
  severity            = 0
  frequency           = "PT1M"
  window_size         = "PT5M"  # 5-min window — no transient spike noise (Issue #9)

  criteria {
    metric_namespace = "microsoft.insights/components"
    metric_name      = "requests/failed"
    aggregation      = "Count"
    operator         = "GreaterThan"
    threshold        = 5
  }

  action { action_group_id = azurerm_monitor_action_group.p0_critical.id }
}

# P1: Service Bus DLQ growing
# LESSON (Issue #8): 4,847 transactions in DLQ for 6 DAYS with no alert.
# Now fires at depth > 10 — catches failures within minutes not days.
resource "azurerm_monitor_metric_alert" "servicebus_dlq_p1" {
  name                = "P1-ServiceBus-DLQ-Growing"
  resource_group_name = var.resource_group_name
  scopes              = [var.servicebus_namespace_id]
  description         = "P1: DLQ accumulating. Check consumer logs for processing errors."
  severity            = 1
  frequency           = "PT5M"
  window_size         = "PT5M"

  criteria {
    metric_namespace = "Microsoft.ServiceBus/namespaces"
    metric_name      = "DeadletteredMessages"
    aggregation      = "Maximum"
    operator         = "GreaterThan"
    threshold        = 10
  }

  action { action_group_id = azurerm_monitor_action_group.p1_high.id }
}

# P1: Azure SQL connections at 70% of limit
# LESSON (Issue #7): Blue-green without cleanup exhausted connection pool.
# Alert at 70% gives time to act before hitting the hard limit.
resource "azurerm_monitor_metric_alert" "sql_connections_p1" {
  name                = "P1-AzureSQL-Connections-70pct"
  resource_group_name = var.resource_group_name
  scopes              = [var.sql_server_id]
  description         = "P1: SQL connections at 70%. Check for idle blue-green standby pods."
  severity            = 1
  frequency           = "PT5M"
  window_size         = "PT10M"

  criteria {
    metric_namespace = "Microsoft.Sql/servers/databases"
    metric_name      = "connection_successful"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = var.sql_connection_limit * 0.70
  }

  action { action_group_id = azurerm_monitor_action_group.p1_high.id }
}
