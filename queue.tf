

///////////////////////////////////////////////////////////[ SERVICE BUS / MESSAGE QUEUE ]/////////////////////////////////////////////////////

resource "azurerm_servicebus_namespace" "this" {
  name                = "${local.project}-servicebus"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  sku                 = local.env.service_bus.sku
  tags                = local.default_tags
}

resource "azurerm_servicebus_queue" "this" {
  name         = "${local.project}-magento-queue"
  namespace_id = azurerm_servicebus_namespace.this.id

  partitioning_enabled  = false
  lock_duration         = "PT5M"
  max_size_in_megabytes = 1024
}
