
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
  frequency           = "PT1M"
  window_size         = "PT5M"
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

resource "azurerm_monitor_metric_alert" "cpu_high_varnish" {
  name                = "${local.project}-varnish-cpu-high"
  resource_group_name = azurerm_resource_group.this.name
  scopes              = [azurerm_linux_virtual_machine_scale_set.this["varnish"].id]
  description         = "Alert when varnish VMSS CPU exceeds 85%"
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"
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

resource "azurerm_monitor_metric_alert" "cpu_high_admin" {
  name                = "${local.project}-admin-cpu-high"
  resource_group_name = azurerm_resource_group.this.name
  scopes              = [azurerm_linux_virtual_machine_scale_set.this["admin"].id]
  description         = "Alert when admin VMSS CPU exceeds 85%"
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"
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

resource "azurerm_monitor_metric_alert" "appgw_5xx" {
  name                = "${local.project}-appgw-5xx"
  resource_group_name = azurerm_resource_group.this.name
  scopes              = [azurerm_application_gateway.this.id]
  description         = "Alert when App Gateway 5xx responses exceed 10 per minute"
  severity            = 1
  frequency           = "PT1M"
  window_size         = "PT5M"
  tags                = local.default_tags

  criteria {
    metric_namespace = "Microsoft.Network/applicationGateways"
    metric_name      = "FailedRequests"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 10
  }

  action {
    action_group_id = azurerm_monitor_action_group.default.id
  }
}

resource "azurerm_monitor_metric_alert" "mysql_storage" {
  name                = "${local.project}-mysql-storage-high"
  resource_group_name = azurerm_resource_group.this.name
  scopes              = [azurerm_mysql_flexible_server.this.id]
  description         = "Alert when MySQL storage utilization exceeds 80%"
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT15M"
  tags                = local.default_tags

  criteria {
    metric_namespace = "Microsoft.DBforMySQL/flexibleServers"
    metric_name      = "storage_percent"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 80
  }

  action {
    action_group_id = azurerm_monitor_action_group.default.id
  }
}

resource "azurerm_monitor_metric_alert" "redis_memory" {
  for_each            = toset(local.env.redis.name)
  name                = "${local.project}-redis-${each.key}-memory-high"
  resource_group_name = azurerm_resource_group.this.name
  scopes              = [azurerm_redis_cache.this[each.key].id]
  description         = "Alert when Redis ${each.key} used memory exceeds 80%"
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"
  tags                = local.default_tags

  criteria {
    metric_namespace = "Microsoft.Cache/Redis"
    metric_name      = "usedmemorypercentage"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 80
  }

  action {
    action_group_id = azurerm_monitor_action_group.default.id
  }
}
