

///////////////////////////////////////////////////////////[ LOCALS ]/////////////////////////////////////////////////////

locals {
  environment = lower(terraform.workspace)

  config_files = {
    developer  = try(file("${abspath(path.root)}/developer.config.yaml"), "")
    staging    = try(file("${abspath(path.root)}/staging.config.yaml"), "")
    production = try(file("${abspath(path.root)}/production.config.yaml"), "")
  }

  env     = yamldecode(local.config_files[local.environment])
  project = lower("${local.env.brand}-${local.env.codename}")

  default_tags = {
    terraform   = "true"
    brand       = local.env.brand
    environment = local.environment
    project     = local.project
  }

  db_name = replace(local.project, "-", "_")

  appgw_backend_pool_name         = "${local.project}-varnish-pool"
  appgw_frontend_port_http_name   = "${local.project}-http-port"
  appgw_frontend_ip_name          = "${local.project}-frontend-ip"
  appgw_http_settings_name        = "${local.project}-http-settings"
  appgw_listener_http_name        = "${local.project}-http-listener"
  appgw_request_routing_http_name = "${local.project}-http-routing"
  appgw_health_probe_name         = "${local.project}-health-probe"
  appgw_waf_policy_name           = "${local.project}-waf-policy"
}

resource "terraform_data" "workspace_validation" {
  lifecycle {
    precondition {
      condition     = contains(["developer", "staging", "production"], local.environment)
      error_message = "Terraform workspace must be 'developer', 'staging', or 'production'. Got: '${local.environment}'. Run: terraform workspace new developer"
    }
  }
}
