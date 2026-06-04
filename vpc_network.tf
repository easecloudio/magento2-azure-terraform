

////////////////////////////////////////////////////////[ VIRTUAL NETWORK ]////////////////////////////////////////////////

resource "azurerm_resource_group" "this" {
  name     = coalesce(local.env.azure.resource_group, "${local.project}-rg")
  location = local.env.azure.location
  tags     = local.default_tags
}

resource "azurerm_virtual_network" "this" {
  name                = "${local.project}-vnet"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  address_space       = [local.env.vnet.cidr_block]
  tags                = local.default_tags
}

resource "azurerm_subnet" "compute" {
  name                 = "${local.project}-compute-subnet"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [cidrsubnet(local.env.vnet.cidr_block, 4, 0)]
}

resource "azurerm_subnet" "data" {
  name                 = "${local.project}-data-subnet"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [cidrsubnet(local.env.vnet.cidr_block, 4, 1)]
  service_endpoints    = ["Microsoft.Storage", "Microsoft.Sql"]
}

resource "azurerm_subnet" "gateway" {
  name                 = "${local.project}-gateway-subnet"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [cidrsubnet(local.env.vnet.cidr_block, 4, 2)]
}

resource "azurerm_subnet" "mysql" {
  name                 = "${local.project}-mysql-subnet"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [cidrsubnet(local.env.vnet.cidr_block, 4, 3)]

  delegation {
    name = "mysql-delegation"
    service_delegation {
      name    = "Microsoft.DBforMySQL/flexibleServers"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

resource "azurerm_subnet" "bastion" {
  name                 = "AzureBastionSubnet"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [cidrsubnet(local.env.vnet.cidr_block, 4, 4)]
}
