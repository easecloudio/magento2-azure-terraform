

///////////////////////////////////////////////////////////[ MANAGED IDENTITY ]/////////////////////////////////////////////////////

resource "azurerm_user_assigned_identity" "compute" {
  name                = "${local.project}-compute-identity"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  tags                = local.default_tags
}

resource "azurerm_role_assignment" "key_vault_reader" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.compute.principal_id
}

resource "azurerm_role_assignment" "blob_contributor" {
  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.compute.principal_id
}
