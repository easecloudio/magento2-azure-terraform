# HA and Cluster Fixes Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make every tier of the Magento 2 Azure stack zone-redundant and clustered, and add a dedicated App Gateway bypass route so admin traffic never passes through Varnish.

**Architecture:** Eight sequential tasks covering compute zone spreading, MySQL zone-redundant HA, Redis replication, OpenSearch 3-node cluster with internal LB, App Gateway path-based admin routing, storage ZRS, and Service Bus Premium. Every task touches one or two files, commits, and pushes.

**Tech Stack:** Terraform >= 1.9, azurerm provider ~> 4.0, Debian 12 ARM64 VMs, Azure Application Gateway WAF_v2, Azure Cache for Redis Premium, Azure MySQL Flexible Server, self-hosted OpenSearch 2.x

---

### Task 1: VMSS zone spreading

**Files:**
- Modify: `compute.tf`

**Context:** Both VMSS resources (varnish, frontend) have no `zones` attribute. Azure places all instances in whatever AZ it picks. A single AZ failure can take the entire compute tier down. Adding `zones = ["1", "2", "3"]` tells Azure to spread instances across all three AZs.

**Step 1: Add zones to the VMSS resource**

In `compute.tf`, inside `azurerm_linux_virtual_machine_scale_set.this`, add after the `upgrade_mode` line:

```hcl
  zones = ["1", "2", "3"]
```

The full resource opening should look like:

```hcl
resource "azurerm_linux_virtual_machine_scale_set" "this" {
  for_each            = local.env.vmss
  name                = "${local.project}-${each.key}-vmss"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  sku                 = each.value.vm_size
  instances           = each.value.desired_capacity
  admin_username      = local.env.brand
  upgrade_mode        = "Rolling"
  zones               = ["1", "2", "3"]
```

**Step 2: Validate and commit**

```bash
cd /Users/safoor/Code/easecloud-opensource/magento2-azure-terraform
terraform validate
terraform fmt -check || terraform fmt
git add compute.tf
git commit -m "fix: spread both VMSS across availability zones 1-2-3"
git push origin main
```

---

### Task 2: App Gateway — zone redundancy and min_capacity 2

**Files:**
- Modify: `load_balancer.tf`

**Context:** The App Gateway public IP and the gateway itself have no `zones` attribute (single-AZ). The `autoscale_configuration` has `min_capacity = 1`, meaning during scale-in there can be one unit — not HA. Both need fixing.

**Step 1: Add zones to the public IP**

In `azurerm_public_ip.appgw`, add:

```hcl
  zones = ["1", "2", "3"]
```

**Step 2: Add zones and raise min_capacity on the App Gateway**

In `azurerm_application_gateway.this`:
- Add `zones = ["1", "2", "3"]` after the `tags` line
- Change `min_capacity = 1` to `min_capacity = 2`

The full public IP and autoscale block should look like:

```hcl
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
```

And inside `azurerm_application_gateway.this`:

```hcl
  zones = ["1", "2", "3"]

  ...

  autoscale_configuration {
    min_capacity = 2
    max_capacity = 4
  }
```

**Step 3: Validate and commit**

```bash
terraform validate
terraform fmt -check || terraform fmt
git add load_balancer.tf
git commit -m "fix: App Gateway zone redundancy, raise min_capacity to 2"
git push origin main
```

---

### Task 3: MySQL zone-redundant HA and geo-redundant backups

**Files:**
- Modify: `developer.config.yaml`
- Modify: `database.tf`

**Context:** MySQL HA is disabled (`high_availability: false`) and `geo_redundant_backup_enabled = false`. This is a single server — a crash or AZ failure is a full database outage. We enable zone-redundant standby and geo-redundant backups (disabled only in developer to keep costs down).

**Step 1: Enable MySQL HA in developer.config.yaml**

Change:

```yaml
  high_availability: false
```

to:

```yaml
  high_availability: true
```

**Step 2: Update database.tf**

Replace the entire `azurerm_mysql_flexible_server.this` resource with:

```hcl
resource "azurerm_mysql_flexible_server" "this" {
  name                         = "${local.project}-mysql"
  resource_group_name          = azurerm_resource_group.this.name
  location                     = azurerm_resource_group.this.location
  administrator_login          = local.env.mysql.admin_login
  administrator_password       = random_password.this["database"].result
  sku_name                     = local.env.mysql.sku
  version                      = local.env.mysql.engine_version
  backup_retention_days        = local.env.mysql.backup_retention_days
  geo_redundant_backup_enabled = local.environment != "developer"
  delegated_subnet_id          = azurerm_subnet.mysql.id
  private_dns_zone_id          = azurerm_private_dns_zone.internal.id
  zone                         = "1"

  high_availability {
    mode                      = local.env.mysql.high_availability ? "ZoneRedundant" : "Disabled"
    standby_availability_zone = local.env.mysql.high_availability ? "2" : null
  }

  storage {
    size_gb           = local.env.mysql.storage_gb
    auto_grow_enabled = true
  }

  tags       = local.default_tags
  depends_on = [azurerm_private_dns_zone_virtual_network_link.this]
}
```

Key changes from current:
- Added `zone = "1"` (primary in AZ1)
- `geo_redundant_backup_enabled = local.environment != "developer"` (enabled in staging/prod)
- `standby_availability_zone = "2"` when HA is on

**Step 3: Validate and commit**

```bash
terraform validate
terraform fmt -check || terraform fmt
git add developer.config.yaml database.tf
git commit -m "fix: MySQL zone-redundant HA, geo-redundant backups in staging/prod"
git push origin main
```

---

### Task 4: Redis — replica + zone redundancy

**Files:**
- Modify: `cache.tf`

**Context:** Redis Premium P1 is provisioned but runs as a single node with no replica. Adding `replicas_per_primary = 1` creates a replica in a different AZ. Adding `zones = ["1", "2"]` pins primary and replica in separate AZs for zone resilience.

**Step 1: Add replicas_per_primary and zones to cache.tf**

In `azurerm_redis_cache.this`, add two attributes after `minimum_tls_version`:

```hcl
  replicas_per_primary = 1
  zones                = ["1", "2"]
```

The full resource should look like:

```hcl
resource "azurerm_redis_cache" "this" {
  for_each             = toset(local.env.redis.name)
  name                 = "${local.project}-redis-${each.key}"
  resource_group_name  = azurerm_resource_group.this.name
  location             = azurerm_resource_group.this.location
  capacity             = local.env.redis.capacity
  family               = local.env.redis.family
  sku_name             = local.env.redis.sku
  non_ssl_port_enabled = false
  minimum_tls_version  = "1.2"
  replicas_per_primary = 1
  zones                = ["1", "2"]
  tags                 = local.default_tags
}
```

**Step 2: Validate and commit**

```bash
terraform validate
terraform fmt -check || terraform fmt
git add cache.tf
git commit -m "fix: Redis Premium — 1 replica per primary, zone-spread across AZ1 and AZ2"
git push origin main
```

---

### Task 5: OpenSearch 3-node cluster with internal load balancer

**Files:**
- Modify: `search.tf` (full rewrite)
- Create: `cloud-init/opensearch.sh`
- Modify: `security_groups.tf` (add port 9300 inter-node rule)

**Context:** OpenSearch is currently a single VM — the biggest SPOF in the stack. Replace it with 3 VMs across AZs 1/2/3, each registering in private DNS automatically (`computer_name = "opensearch-N"` + `registration_enabled = true` on the private DNS zone link). An internal Standard Load Balancer sits in front on port 9200 so Magento has a single stable endpoint. Nodes discover each other via DNS names `opensearch-0.<brand>.internal` etc.

**Step 1: Create cloud-init/opensearch.sh**

Create `/Users/safoor/Code/easecloud-opensource/magento2-azure-terraform/cloud-init/opensearch.sh` with:

```bash
#!/bin/bash
set -euo pipefail

NODE_INDEX="${node_index}"
BRAND="${brand}"
PROJECT="${project}"
VERSION="${opensearch_version}"

hostnamectl set-hostname "opensearch-$${NODE_INDEX}"
echo "127.0.0.1 opensearch-$${NODE_INDEX} opensearch-$${NODE_INDEX}.$${BRAND}.internal" >> /etc/hosts

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq openjdk-17-jre-headless curl

curl -fsSL "https://artifacts.opensearch.org/releases/bundle/opensearch/2.x/opensearch-$${VERSION}-linux-arm64.tar.gz" \
  -o /tmp/opensearch.tar.gz
mkdir -p /opt/opensearch
tar -xzf /tmp/opensearch.tar.gz -C /opt/opensearch --strip-components=1
/opt/opensearch/opensearch-tar-install.sh

cat > /opt/opensearch/config/opensearch.yml <<EOF
cluster.name: ${project}-cluster
node.name: opensearch-$${NODE_INDEX}
network.host: 0.0.0.0
http.port: 9200
transport.port: 9300

discovery.seed_hosts:
  - opensearch-0.${brand}.internal:9300
  - opensearch-1.${brand}.internal:9300
  - opensearch-2.${brand}.internal:9300

cluster.initial_cluster_manager_nodes:
  - opensearch-0
  - opensearch-1
  - opensearch-2

plugins.security.disabled: true
EOF

echo "OpenSearch node $${NODE_INDEX} initialized: ${project}" >> /var/log/cloud-init-custom.log
```

Note on escaping: `$${...}` is a literal `${...}` in shell (Terraform templatefile escaping). `${...}` is Terraform interpolation evaluated at plan time.

**Step 2: Rewrite search.tf**

Replace the entire content of `search.tf` with:

```hcl


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
    node_index        = count.index
    brand             = local.env.brand
    project           = local.project
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
```

**Step 3: Add port 9300 inter-node rule to the data NSG**

In `security_groups.tf`, in `azurerm_network_security_group.data`, after the `allow-opensearch-from-compute` rule (priority 120) and before `deny-all-inbound` (priority 200), add:

```hcl
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
```

This allows OpenSearch nodes to form a cluster (transport on 9300) within the data subnet.

**Step 4: Validate and commit**

```bash
terraform validate
terraform fmt -check || terraform fmt
git add search.tf cloud-init/opensearch.sh security_groups.tf
git commit -m "feat: OpenSearch 3-node cluster across AZs with internal LB"
git push origin main
```

---

### Task 6: Admin bypass route — frontend VMSS direct path in App Gateway

**Files:**
- Modify: `locals.tf`
- Modify: `load_balancer.tf`
- Modify: `compute.tf`
- Modify: `developer.config.yaml`

**Context:** All traffic currently goes through Varnish (cached). Magento's admin panel must never be served from cache — admin requests must bypass Varnish and hit the Frontend VMSS directly. We achieve this with a second App Gateway backend pool (`frontend-direct`) and URL path-based routing: `/${admin_path}/*` → frontend VMSS, everything else → Varnish.

Also: add an optional `waf.admin_allowed_ips` config key that, when set, restricts admin path access at the WAF layer.

**Step 1: Add new locals to locals.tf**

In `locals.tf`, after the existing local definitions, add:

```hcl
  appgw_frontend_backend_pool_name  = "${local.project}-frontend-pool"
  appgw_frontend_http_settings_name = "${local.project}-frontend-settings"
  appgw_frontend_probe_name         = "${local.project}-frontend-probe"
  appgw_url_path_map_name           = "${local.project}-path-map"
  appgw_admin_path_rule_name        = "${local.project}-admin-rule"
```

**Step 2: Update load_balancer.tf**

This is the most extensive change. Read the current file first, then apply all changes.

**2a. Add the WAF admin IP restriction custom rule (dynamic, optional):**

In `azurerm_web_application_firewall_policy.this`, after the existing `dynamic "custom_rules"` block (GeoBlock), add a second dynamic block:

```hcl
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
```

**2b. Add the frontend-direct backend pool to the App Gateway:**

After the existing `backend_address_pool` block (varnish pool), add:

```hcl
  backend_address_pool {
    name = local.appgw_frontend_backend_pool_name
  }
```

**2c. Add frontend HTTP settings:**

After the existing `backend_http_settings` block, add:

```hcl
  backend_http_settings {
    name                  = local.appgw_frontend_http_settings_name
    cookie_based_affinity = "Disabled"
    port                  = 80
    protocol              = "Http"
    request_timeout       = 60

    probe_name = local.appgw_frontend_probe_name
  }
```

**2d. Add frontend health probe:**

After the existing `probe` block, add:

```hcl
  probe {
    name                = local.appgw_frontend_probe_name
    protocol            = "Http"
    host                = local.env.domain
    path                = "/${random_string.this["health_check"].result}"
    interval            = 30
    timeout             = 30
    unhealthy_threshold = 3
  }
```

**2e. Add the URL path map:**

After the `probe` blocks, add:

```hcl
  url_path_map {
    name                               = local.appgw_url_path_map_name
    default_backend_address_pool_name  = local.appgw_backend_pool_name
    default_backend_http_settings_name = local.appgw_http_settings_name

    path_rule {
      name                       = local.appgw_admin_path_rule_name
      paths                      = ["/${random_string.this["admin_path"].result}/*", "/${random_string.this["admin_path"].result}"]
      backend_address_pool_name  = local.appgw_frontend_backend_pool_name
      backend_http_settings_name = local.appgw_frontend_http_settings_name
    }
  }
```

**2f. Change the routing rule from Basic to PathBasedRouting:**

Replace the existing `request_routing_rule` block:

```hcl
  request_routing_rule {
    name                       = local.appgw_request_routing_http_name
    rule_type                  = "PathBasedRouting"
    priority                   = 100
    http_listener_name         = local.appgw_listener_http_name
    url_path_map_name          = local.appgw_url_path_map_name
  }
```

(Remove `backend_address_pool_name` and `backend_http_settings_name` — those move into the path map default.)

**Step 3: Update compute.tf — associate Frontend VMSS with frontend-direct pool**

In `compute.tf`, update the `application_gateway_backend_address_pool_ids` expression to handle the frontend VMSS:

```hcl
      application_gateway_backend_address_pool_ids = each.key == "varnish" ? [
        one([for pool in azurerm_application_gateway.this.backend_address_pool
             : pool.id if pool.name == local.appgw_backend_pool_name])
        ] : each.key == "frontend" ? [
        one([for pool in azurerm_application_gateway.this.backend_address_pool
             : pool.id if pool.name == local.appgw_frontend_backend_pool_name])
      ] : null
```

**Step 4: Add admin_allowed_ips to developer.config.yaml**

In `developer.config.yaml`, update the `waf` block to add the new key (empty list = restriction disabled):

```yaml
waf:
  restricted_countries:
    - "CN"
    - "RU"
    - "IR"
    - "KP"
    - "SD"
    - "SY"
    - "CU"
  admin_allowed_ips: []  # Set to office/VPN CIDRs e.g. ["1.2.3.4/32"] to restrict admin access
```

**Step 5: Validate and commit**

```bash
terraform validate
terraform fmt -check || terraform fmt
git add locals.tf load_balancer.tf compute.tf developer.config.yaml
git commit -m "feat: admin bypass route — frontend VMSS direct pool, path-based routing, optional WAF IP restriction"
git push origin main
```

---

### Task 7: Storage account replication — LRS to ZRS

**Files:**
- Modify: `storage.tf`
- Modify: `filesystem.tf`

**Context:** Both storage accounts use LRS (single datacenter). If the datacenter has an AZ failure, blob media and NFS shares go offline. ZRS (zone-redundant) replicates synchronously across 3 AZs in the region. Standard ZRS is supported for blob; Premium ZRS is supported for FileStorage (Premium NFS).

**Step 1: Update storage.tf blob account**

In `azurerm_storage_account.this`, change:

```hcl
  account_replication_type = "LRS"
```

to:

```hcl
  account_replication_type = "ZRS"
```

**Step 2: Update filesystem.tf NFS account**

In `azurerm_storage_account.nfs`, change:

```hcl
  account_replication_type   = "LRS"
```

to:

```hcl
  account_replication_type   = "ZRS"
```

**Step 3: Validate and commit**

```bash
terraform validate
terraform fmt -check || terraform fmt
git add storage.tf filesystem.tf
git commit -m "fix: storage accounts LRS → ZRS for zone-redundant media and NFS"
git push origin main
```

---

### Task 8: Service Bus — Premium SKU with zone redundancy

**Files:**
- Modify: `developer.config.yaml`
- Modify: `queue.tf`

**Context:** Service Bus Standard has no zone redundancy. Premium SKU adds zone redundancy and dedicated capacity. We upgrade the SKU in config and add `zone_redundant = true` + `premium_messaging_partitions = 1` to the namespace (both require Premium).

**Step 1: Update developer.config.yaml**

Change:

```yaml
service_bus:
  sku: "Standard"
```

to:

```yaml
service_bus:
  sku: "Premium"
```

**Step 2: Update queue.tf**

In `azurerm_servicebus_namespace.this`, add two attributes after `sku`:

```hcl
  zone_redundant               = local.env.service_bus.sku == "Premium"
  premium_messaging_partitions = local.env.service_bus.sku == "Premium" ? 1 : 0
```

The full resource should be:

```hcl
resource "azurerm_servicebus_namespace" "this" {
  name                         = "${local.project}-servicebus"
  resource_group_name          = azurerm_resource_group.this.name
  location                     = azurerm_resource_group.this.location
  sku                          = local.env.service_bus.sku
  zone_redundant               = local.env.service_bus.sku == "Premium"
  premium_messaging_partitions = local.env.service_bus.sku == "Premium" ? 1 : 0
  tags                         = local.default_tags
}
```

**Step 3: Validate and commit**

```bash
terraform validate
terraform fmt -check || terraform fmt
git add developer.config.yaml queue.tf
git commit -m "fix: Service Bus Premium SKU with zone redundancy"
git push origin main
```

---

## Summary

| Task | Files | Change |
|---|---|---|
| 1 | `compute.tf` | `zones = ["1","2","3"]` on both VMSS |
| 2 | `load_balancer.tf` | Public IP zones, App GW zones, min_capacity 1→2 |
| 3 | `developer.config.yaml`, `database.tf` | MySQL HA on, standby AZ2, geo-backup in staging/prod |
| 4 | `cache.tf` | Redis replica + AZ1/AZ2 zone spread |
| 5 | `search.tf`, `cloud-init/opensearch.sh`, `security_groups.tf` | 3-node OpenSearch cluster + internal LB + port 9300 rule |
| 6 | `locals.tf`, `load_balancer.tf`, `compute.tf`, `developer.config.yaml` | Admin bypass path rule, frontend-direct backend pool |
| 7 | `storage.tf`, `filesystem.tf` | LRS → ZRS |
| 8 | `developer.config.yaml`, `queue.tf` | Service Bus Premium + zone_redundant |
