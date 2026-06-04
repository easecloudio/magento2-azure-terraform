

///////////////////////////////////////////////////////////[ SEARCH — OPENSEARCH CLUSTER ]/////////////////////////////////////////////////////

resource "azurerm_network_interface" "opensearch" {
  count               = 3
  name                = "${local.project}-opensearch-${count.index}-nic"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  tags                = local.default_tags

  ip_configuration {
    name                          = "primary"
    subnet_id                     = azurerm_subnet.data.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_linux_virtual_machine" "opensearch" {
  count               = 3
  name                = "${local.project}-opensearch-${count.index}"
  computer_name       = "opensearch-${count.index}"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  size                = local.env.opensearch.vm_size
  admin_username      = local.env.brand
  zone                = tostring(count.index + 1)

  admin_ssh_key {
    username   = local.env.brand
    public_key = local.env.ssh_public_key
  }

  network_interface_ids = [azurerm_network_interface.opensearch[count.index].id]

  source_image_reference {
    publisher = "Debian"
    offer     = "debian-12"
    sku       = "12-gen2"
    version   = "latest"
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = local.env.opensearch.disk_size_gb
  }

  identity {
    type = "SystemAssigned"
  }

  custom_data = base64encode(templatefile("${path.module}/cloud-init/opensearch.sh", {
    node_index         = count.index
    brand              = local.env.brand
    project            = local.project
    opensearch_version = local.env.opensearch.version
  }))

  tags = local.default_tags
}

///////////////////////////////////////////////////////////[ OPENSEARCH INTERNAL LOAD BALANCER ]/////////////////////////////////////////////////////

resource "azurerm_lb" "opensearch" {
  name                = "${local.project}-opensearch-lb"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  sku                 = "Standard"
  tags                = local.default_tags

  frontend_ip_configuration {
    name                          = "opensearch-frontend"
    subnet_id                     = azurerm_subnet.data.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_lb_backend_address_pool" "opensearch" {
  name            = "${local.project}-opensearch-pool"
  loadbalancer_id = azurerm_lb.opensearch.id
}

resource "azurerm_lb_probe" "opensearch" {
  name            = "${local.project}-opensearch-probe"
  loadbalancer_id = azurerm_lb.opensearch.id
  protocol        = "Http"
  port            = 9200
  request_path    = "/_cluster/health"
}

resource "azurerm_lb_rule" "opensearch" {
  name                           = "${local.project}-opensearch-rule"
  loadbalancer_id                = azurerm_lb.opensearch.id
  protocol                       = "Tcp"
  frontend_port                  = 9200
  backend_port                   = 9200
  frontend_ip_configuration_name = "opensearch-frontend"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.opensearch.id]
  probe_id                       = azurerm_lb_probe.opensearch.id
}

resource "azurerm_network_interface_backend_address_pool_association" "opensearch" {
  count                   = 3
  network_interface_id    = azurerm_network_interface.opensearch[count.index].id
  ip_configuration_name   = "primary"
  backend_address_pool_id = azurerm_lb_backend_address_pool.opensearch.id
}
