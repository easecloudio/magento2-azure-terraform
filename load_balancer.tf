
///////////////////////////////////////////////////////////[ AZURE APPLICATION GATEWAY ]/////////////////////////////////////////////////////

resource "azurerm_public_ip" "appgw" {
  name                = "${local.project}-appgw-pip"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  allocation_method   = "Static"
  sku                 = "Standard"
  domain_name_label   = "${local.project}-appgw"
  zones               = ["1", "2", "3"]
  tags                = local.default_tags
}


resource "azurerm_web_application_firewall_policy" "this" {
  name                = local.appgw_waf_policy_name
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  tags                = local.default_tags

  managed_rules {
    managed_rule_set {
      type    = "OWASP"
      version = "3.2"
    }
  }

  dynamic "custom_rules" {
    for_each = length(try(local.env.waf.restricted_countries, [])) > 0 ? [1] : []
    content {
      name      = "GeoBlock"
      priority  = 1
      rule_type = "MatchRule"
      action    = "Block"

      match_conditions {
        match_variables {
          variable_name = "RemoteAddr"
        }
        operator           = "GeoMatch"
        negation_condition = false
        match_values       = local.env.waf.restricted_countries
      }
    }
  }

  dynamic "custom_rules" {
    for_each = length(try(local.env.waf.admin_allowed_ips, [])) > 0 ? [1] : []
    content {
      name      = "AdminIPRestriction"
      priority  = 2
      rule_type = "MatchRule"
      action    = "Block"

      match_conditions {
        match_variables {
          variable_name = "RequestUri"
        }
        operator     = "BeginsWith"
        match_values = ["/${random_string.this["admin_path"].result}/"]
      }

      match_conditions {
        match_variables {
          variable_name = "RemoteAddr"
        }
        operator           = "IPMatch"
        negation_condition = true
        match_values       = local.env.waf.admin_allowed_ips
      }
    }
  }

  policy_settings {
    enabled                     = true
    mode                        = "Prevention"
    request_body_check          = true
    max_request_body_size_in_kb = 128
    file_upload_limit_in_mb     = 100
  }
}

resource "azurerm_application_gateway" "this" {
  name                = "${local.project}-appgw"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  firewall_policy_id  = azurerm_web_application_firewall_policy.this.id
  tags                = local.default_tags
  zones               = ["1", "2", "3"]

  sku {
    name = "WAF_v2"
    tier = "WAF_v2"
  }

  autoscale_configuration {
    min_capacity = 2
    max_capacity = 4
  }

  gateway_ip_configuration {
    name      = "${local.project}-gwip"
    subnet_id = azurerm_subnet.gateway.id
  }

  frontend_ip_configuration {
    name                 = local.appgw_frontend_ip_name
    public_ip_address_id = azurerm_public_ip.appgw.id
  }

  frontend_port {
    name = local.appgw_frontend_port_http_name
    port = 80
  }

  backend_address_pool {
    name = local.appgw_backend_pool_name
  }

  backend_address_pool {
    name = local.appgw_admin_backend_pool_name
  }

  backend_http_settings {
    name                  = local.appgw_http_settings_name
    cookie_based_affinity = "Disabled"
    port                  = 80
    protocol              = "Http"
    request_timeout       = 60

    probe_name = local.appgw_health_probe_name
  }

  backend_http_settings {
    name                  = local.appgw_admin_http_settings_name
    cookie_based_affinity = "Disabled"
    port                  = 80
    protocol              = "Http"
    request_timeout       = 60

    probe_name = local.appgw_admin_probe_name
  }

  probe {
    name                = local.appgw_health_probe_name
    protocol            = "Http"
    host                = local.env.domain
    path                = "/${random_string.this["health_check"].result}"
    interval            = 30
    timeout             = 30
    unhealthy_threshold = 3
  }

  probe {
    name                = local.appgw_admin_probe_name
    protocol            = "Http"
    host                = local.env.domain
    path                = "/${random_string.this["health_check"].result}"
    interval            = 30
    timeout             = 30
    unhealthy_threshold = 3
  }

  http_listener {
    name                           = local.appgw_listener_http_name
    frontend_ip_configuration_name = local.appgw_frontend_ip_name
    frontend_port_name             = local.appgw_frontend_port_http_name
    protocol                       = "Http"
  }

  url_path_map {
    name                               = local.appgw_url_path_map_name
    default_backend_address_pool_name  = local.appgw_backend_pool_name
    default_backend_http_settings_name = local.appgw_http_settings_name

    path_rule {
      name                       = local.appgw_admin_path_rule_name
      paths                      = ["/${random_string.this["admin_path"].result}/*", "/${random_string.this["admin_path"].result}"]
      backend_address_pool_name  = local.appgw_admin_backend_pool_name
      backend_http_settings_name = local.appgw_admin_http_settings_name
    }
  }

  request_routing_rule {
    name               = local.appgw_request_routing_http_name
    rule_type          = "PathBasedRouting"
    priority           = 100
    http_listener_name = local.appgw_listener_http_name
    url_path_map_name  = local.appgw_url_path_map_name
  }
}
