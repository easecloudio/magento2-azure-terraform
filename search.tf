

///////////////////////////////////////////////////////////[ SEARCH ]/////////////////////////////////////////////////////

# Self-hosted OpenSearch VM (recommended for Magento compatibility)
resource "azurerm_network_interface" "opensearch" {
  name                = "${local.project}-opensearch-nic"
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
  name                = "${local.project}-opensearch"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  size                = local.env.opensearch.vm_size
  admin_username      = local.env.brand

  admin_ssh_key {
    username   = local.env.brand
    public_key = local.env.ssh_public_key
  }

  network_interface_ids = [azurerm_network_interface.opensearch.id]

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

  custom_data = base64encode(<<-EOT
    #!/bin/bash
    set -euo pipefail
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq openjdk-17-jre-headless
    curl -fsSL https://artifacts.opensearch.org/releases/bundle/opensearch/2.x/opensearch-${local.env.opensearch.version}-linux-arm64.tar.gz \
      -o /tmp/opensearch.tar.gz
    mkdir -p /opt/opensearch
    tar -xzf /tmp/opensearch.tar.gz -C /opt/opensearch --strip-components=1
    /opt/opensearch/opensearch-tar-install.sh
  EOT
  )

  tags = local.default_tags
}
