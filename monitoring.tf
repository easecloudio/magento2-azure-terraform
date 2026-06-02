
///////////////////////////////////////////////////////////[ AZURE MONITOR ]/////////////////////////////////////////////////////

resource "azurerm_monitor_action_group" "default" {
  name                = "${local.project}-action-group"
  resource_group_name = azurerm_resource_group.this.name
  short_name          = substr(local.project, 0, 12)
  tags                = local.default_tags

  email_receiver {
    name          = "admin-email"
    email_address = local.env.admin_email
  }
}

resource "azurerm_monitor_metric_alert" "cpu_high_frontend" {
  name                = "${local.project}-frontend-cpu-high"
  resource_group_name = azurerm_resource_group.this.name
  scopes              = [azurerm_linux_virtual_machine_scale_set.this["frontend"].id]
  description         = "Alert when frontend VMSS CPU exceeds 85%"
  severity            = 2
  tags                = local.default_tags

  criteria {
    metric_namespace = "Microsoft.Compute/virtualMachineScaleSets"
    metric_name      = "Percentage CPU"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 85
  }

  action {
    action_group_id = azurerm_monitor_action_group.default.id
  }
}
