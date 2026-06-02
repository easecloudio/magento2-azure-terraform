

///////////////////////////////////////////////////////////[ REDIS CACHE ]/////////////////////////////////////////////////////

resource "azurerm_redis_cache" "this" {
  for_each            = toset(local.env.redis.name)
  name                = "${local.project}-redis-${each.key}"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  capacity            = local.env.redis.capacity
  family              = local.env.redis.family
  sku_name            = local.env.redis.sku
  enable_non_ssl_port = false
  minimum_tls_version = "1.2"
  tags                = local.default_tags
}
