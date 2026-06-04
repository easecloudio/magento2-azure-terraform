

////////////////////////////////////////////////////////[ NETWORK SECURITY GROUPS ]////////////////////////////////////////

# # ---------------------------------------------------------------------------------------------------------------------#
# Compute NSG — allows HTTP from gateway subnet, denies SSH
# # ---------------------------------------------------------------------------------------------------------------------#
resource "azurerm_network_security_group" "compute" {
  name                = "${local.project}-compute-nsg"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  tags                = local.default_tags

  security_rule {
    name                       = "allow-http-from-gateway"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = azurerm_subnet.gateway.address_prefixes[0]
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow-internal-varnish-to-frontend"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = azurerm_subnet.compute.address_prefixes[0]
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "deny-ssh"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "compute" {
  subnet_id                 = azurerm_subnet.compute.id
  network_security_group_id = azurerm_network_security_group.compute.id
}

# # ---------------------------------------------------------------------------------------------------------------------#
# Data NSG — allows MySQL 3306 and Redis 6379 from compute subnet only
# # ---------------------------------------------------------------------------------------------------------------------#
resource "azurerm_network_security_group" "data" {
  name                = "${local.project}-data-nsg"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  tags                = local.default_tags

  security_rule {
    name                       = "allow-mysql-from-compute"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3306"
    source_address_prefix      = azurerm_subnet.compute.address_prefixes[0]
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow-redis-from-compute"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "6379"
    source_address_prefix      = azurerm_subnet.compute.address_prefixes[0]
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow-opensearch-from-compute"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "9200"
    source_address_prefix      = azurerm_subnet.compute.address_prefixes[0]
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow-opensearch-transport-internal"
    priority                   = 130
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "9300"
    source_address_prefix      = azurerm_subnet.data.address_prefixes[0]
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "deny-all-inbound"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "data" {
  subnet_id                 = azurerm_subnet.data.id
  network_security_group_id = azurerm_network_security_group.data.id
}

# # ---------------------------------------------------------------------------------------------------------------------#
# Gateway NSG — allows App Gateway health probe ports 65200-65535
# # ---------------------------------------------------------------------------------------------------------------------#
resource "azurerm_network_security_group" "gateway" {
  name                = "${local.project}-gateway-nsg"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  tags                = local.default_tags

  security_rule {
    name                       = "allow-appgw-health-probes"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "65200-65535"
    source_address_prefix      = "GatewayManager"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow-http-https-inbound"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["80", "443"]
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "gateway" {
  subnet_id                 = azurerm_subnet.gateway.id
  network_security_group_id = azurerm_network_security_group.gateway.id
}
