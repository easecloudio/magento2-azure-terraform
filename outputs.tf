
///////////////////////////////////////////////////////////[ OUTPUTS ]/////////////////////////////////////////////////////

output "load_balancer_ip" {
  description = "Public IP of the Azure Application Gateway"
  value       = azurerm_public_ip.appgw.ip_address
}

output "frontdoor_hostname" {
  description = "Azure Front Door CDN endpoint hostname"
  value       = azurerm_cdn_frontdoor_endpoint.this.host_name
}

output "mysql_endpoint" {
  description = "Azure MySQL Flexible Server FQDN"
  value       = azurerm_mysql_flexible_server.this.fqdn
}

output "redis_endpoints" {
  description = "Azure Cache for Redis hostnames keyed by name (session, cache)"
  value = {
    for k, v in azurerm_redis_cache.this :
    k => v.hostname
  }
}

output "blob_storage_containers" {
  description = "Blob Storage container names"
  value       = keys(azurerm_storage_container.this)
}

output "blob_storage_account_name" {
  description = "Azure Storage Account name for blob containers"
  value       = azurerm_storage_account.this.name
}

output "nfs_storage_account_name" {
  description = "Azure Storage Account name for NFS file shares"
  value       = azurerm_storage_account.nfs.name
}

output "project" {
  description = "Project name derived from brand + codename"
  value       = local.project
}

output "environment" {
  description = "Active Terraform workspace / environment name"
  value       = local.environment
}

output "dns_zone_name_servers" {
  description = "Delegate your domain to these Azure nameservers at your registrar"
  value       = azurerm_dns_zone.public.name_servers
}
