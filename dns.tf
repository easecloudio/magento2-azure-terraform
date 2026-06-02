

///////////////////////////////////////////////////////////[ PUBLIC DNS ]/////////////////////////////////////////////////////

resource "azurerm_dns_zone" "public" {
  name                = local.env.domain
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.default_tags
}
