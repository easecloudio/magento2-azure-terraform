

///////////////////////////////////////////////////////////[ MYSQL DATABASE ]/////////////////////////////////////////////////////

resource "azurerm_mysql_flexible_server" "this" {
  name                         = "${local.project}-mysql"
  resource_group_name          = azurerm_resource_group.this.name
  location                     = azurerm_resource_group.this.location
  administrator_login          = local.env.mysql.admin_login
  administrator_password       = random_password.this["database"].result
  sku_name                     = local.env.mysql.sku
  version                      = local.env.mysql.engine_version
  backup_retention_days        = local.env.mysql.backup_retention_days
  geo_redundant_backup_enabled = false

  high_availability {
    mode = local.env.mysql.high_availability ? "ZoneRedundant" : "Disabled"
  }

  storage {
    size_gb           = local.env.mysql.storage_gb
    auto_grow_enabled = true
  }

  tags = local.default_tags
}

resource "azurerm_mysql_flexible_server_configuration" "this" {
  for_each            = { for p in local.env.mysql.parameters : p.name => p.value }
  resource_group_name = azurerm_resource_group.this.name
  server_name         = azurerm_mysql_flexible_server.this.name
  name                = each.key
  value               = each.value
}
