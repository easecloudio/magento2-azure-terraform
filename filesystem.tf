
///////////////////////////////////////////////////////////[ AZURE FILES (NFS) ]/////////////////////////////////////////////////////

resource "azurerm_storage_account" "nfs" {
  name                       = "${substr(replace(local.project, "-", ""), 0, 19)}nfssa"
  resource_group_name        = azurerm_resource_group.this.name
  location                   = azurerm_resource_group.this.location
  account_tier               = "Premium"
  account_replication_type   = "ZRS"
  account_kind               = "FileStorage"
  https_traffic_only_enabled = false
  tags                       = local.default_tags
}

resource "azurerm_storage_share" "this" {
  for_each           = local.env.azure_files.shares
  name               = "${local.project}-${each.key}"
  storage_account_id = azurerm_storage_account.nfs.id
  quota              = each.value.quota_gb
  enabled_protocol   = "NFS"
}
