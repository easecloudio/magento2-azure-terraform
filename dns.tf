

///////////////////////////////////////////////////////////[ PUBLIC DNS ]/////////////////////////////////////////////////////

resource "azurerm_dns_zone" "public" {
  name                = local.env.domain
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.default_tags
}

resource "azurerm_dns_cname_record" "frontdoor" {
  name                = "www"
  zone_name           = azurerm_dns_zone.public.name
  resource_group_name = azurerm_resource_group.this.name
  ttl                 = 300
  record              = azurerm_cdn_frontdoor_endpoint.this.host_name
}

resource "azurerm_dns_txt_record" "frontdoor_validation" {
  name                = "_dnsauth"
  zone_name           = azurerm_dns_zone.public.name
  resource_group_name = azurerm_resource_group.this.name
  ttl                 = 300

  record {
    value = azurerm_cdn_frontdoor_custom_domain.this.validation_token
  }
}

resource "azurerm_dns_txt_record" "frontdoor_validation_www" {
  name                = "_dnsauth.www"
  zone_name           = azurerm_dns_zone.public.name
  resource_group_name = azurerm_resource_group.this.name
  ttl                 = 300

  record {
    value = azurerm_cdn_frontdoor_custom_domain.www.validation_token
  }
}

resource "azurerm_dns_a_record" "appgw" {
  name                = "@"
  zone_name           = azurerm_dns_zone.public.name
  resource_group_name = azurerm_resource_group.this.name
  ttl                 = 300
  target_resource_id  = azurerm_cdn_frontdoor_endpoint.this.id
}
