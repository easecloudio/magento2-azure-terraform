

///////////////////////////////////////////////////////////[ SERVICE DISCOVERY - PRIVATE DNS ]/////////////////////////////////////////////////////

resource "azurerm_private_dns_zone" "internal" {
  name                = "${local.env.brand}.internal"
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.default_tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "this" {
  name                  = "${local.project}-vnet-link"
  resource_group_name   = azurerm_resource_group.this.name
  private_dns_zone_name = azurerm_private_dns_zone.internal.name
  virtual_network_id    = azurerm_virtual_network.this.id
  registration_enabled  = true
  tags                  = local.default_tags
}
