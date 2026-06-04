

///////////////////////////////////////////////////////////[ AZURE KEY VAULT + SECRETS ]/////////////////////////////////////////////////////

resource "azurerm_key_vault" "this" {
  name                     = "${substr(replace(local.project, "-", ""), 0, 21)}-kv"
  resource_group_name      = azurerm_resource_group.this.name
  location                 = azurerm_resource_group.this.location
  tenant_id                = data.azurerm_client_config.current.tenant_id
  sku_name                 = "standard"
  purge_protection_enabled = local.environment != "developer"
  tags                     = local.default_tags
}

resource "azurerm_key_vault_access_policy" "terraform" {
  key_vault_id = azurerm_key_vault.this.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_client_config.current.object_id

  secret_permissions = ["Get", "List", "Set", "Delete", "Purge", "Recover"]
}

resource "azurerm_key_vault_access_policy" "compute" {
  key_vault_id = azurerm_key_vault.this.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_user_assigned_identity.compute.principal_id

  secret_permissions = ["Get", "List"]
}

locals {
  secrets = {
    mysql-password  = random_password.this["database"].result
    redis-password  = random_password.this["redis"].result
    admin-path      = random_string.this["admin_path"].result
    health-check    = random_string.this["health_check"].result
    security-header = random_uuid.this.result
  }
}

resource "azurerm_key_vault_secret" "this" {
  for_each     = local.secrets
  name         = each.key
  value        = each.value
  key_vault_id = azurerm_key_vault.this.id

  depends_on = [azurerm_key_vault_access_policy.terraform]
}
