
///////////////////////////////////////////////////////////[ AZURE FRONT DOOR CDN ]/////////////////////////////////////////////////////

resource "azurerm_cdn_frontdoor_profile" "this" {
  name                = "${local.project}-fd"
  resource_group_name = azurerm_resource_group.this.name
  sku_name            = "Standard_AzureFrontDoor"
  tags                = local.default_tags
}

resource "azurerm_cdn_frontdoor_endpoint" "this" {
  name                     = "${local.project}-fd-endpoint"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.this.id
  tags                     = local.default_tags
}

resource "azurerm_cdn_frontdoor_origin_group" "this" {
  name                     = "${local.project}-origin-group"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.this.id
  session_affinity_enabled = false

  load_balancing {
    sample_size                 = 4
    successful_samples_required = 3
  }

  health_probe {
    path                = "/${random_string.this["health_check"].result}"
    request_type        = "GET"
    protocol            = "Http"
    interval_in_seconds = 30
  }
}

resource "azurerm_cdn_frontdoor_origin" "appgw" {
  name                          = "${local.project}-appgw-origin"
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.this.id
  enabled                       = true

  certificate_name_check_enabled = false
  host_name                      = azurerm_public_ip.appgw.fqdn
  http_port                      = 80
  https_port                     = 443
  origin_host_header             = local.env.domain
  priority                       = 1
  weight                         = 1000
}

resource "azurerm_cdn_frontdoor_route" "this" {
  name                          = "${local.project}-route"
  cdn_frontdoor_endpoint_id     = azurerm_cdn_frontdoor_endpoint.this.id
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.this.id
  cdn_frontdoor_origin_ids        = [azurerm_cdn_frontdoor_origin.appgw.id]
  cdn_frontdoor_custom_domain_ids = [azurerm_cdn_frontdoor_custom_domain.this.id]
  enabled                         = true

  forwarding_protocol    = "HttpOnly"
  https_redirect_enabled = true
  patterns_to_match      = ["/*"]
  supported_protocols    = ["Http", "Https"]

  cache {
    query_string_caching_behavior = "IgnoreSpecifiedQueryStrings"
    query_strings                 = ["utm_source", "utm_medium", "utm_campaign", "gclid", "fbclid"]
    compression_enabled           = true
    content_types_to_compress     = [
      "text/html",
      "text/css",
      "text/javascript",
      "application/javascript",
      "application/json",
      "image/svg+xml",
    ]
  }
}

resource "azurerm_cdn_frontdoor_custom_domain" "this" {
  name                     = "${local.project}-custom-domain"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.this.id
  host_name                = local.env.domain

  tls {
    certificate_type = "ManagedCertificate"
  }
}

resource "azurerm_cdn_frontdoor_custom_domain_association" "this" {
  cdn_frontdoor_custom_domain_id = azurerm_cdn_frontdoor_custom_domain.this.id
  cdn_frontdoor_route_ids        = [azurerm_cdn_frontdoor_route.this.id]
}
