
///////////////////////////////////////////////////////////[ BLOB STORAGE ]/////////////////////////////////////////////////////

resource "azurerm_storage_account" "this" {
  name                     = "${substr(replace(local.project, "-", ""), 0, 22)}sa"
  resource_group_name      = azurerm_resource_group.this.name
  location                 = azurerm_resource_group.this.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"
  tags                     = local.default_tags
}

resource "azurerm_storage_container" "this" {
  for_each              = toset(local.env.blob_storage.containers)
  name                  = each.key
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = "private"
}

resource "azurerm_storage_queue" "release_events" {
  name                 = "release-events"
  storage_account_name = azurerm_storage_account.this.name
}
