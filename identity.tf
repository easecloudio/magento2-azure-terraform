

///////////////////////////////////////////////////////////[ MANAGED IDENTITY ]/////////////////////////////////////////////////////

resource "azurerm_user_assigned_identity" "compute" {
  name                = "${local.project}-compute-identity"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  tags                = local.default_tags
}
