

///////////////////////////////////////////////////////////[ AZURE BASTION ]//////////////////////////////////////////////////

resource "azurerm_public_ip" "bastion" {
  name                = "${local.project}-bastion-pip"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.default_tags
}

resource "azurerm_bastion_host" "this" {
  name                = "${local.project}-bastion"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  tags                = local.default_tags

  ip_configuration {
    name                 = "bastion-ip-config"
    subnet_id            = azurerm_subnet.bastion.id
    public_ip_address_id = azurerm_public_ip.bastion.id
  }
}
