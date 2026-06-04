# Architecture Fixes Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix ten architecture gaps identified in the open-source Magento 2 Azure Terraform module, from critical routing failures to security hardening.

**Architecture:** Single-flat-file Terraform layout (no modules); each `.tf` file owns one concern. Changes are additive edits to existing files plus two new files (`bastion.tf`, `backend.tf.example`). All fixes must pass `terraform validate` and `terraform fmt -check`.

**Tech Stack:** Terraform >= 1.9, azurerm provider ~> 4.0, random provider ~> 3.6

---

### Task 1: Wire Varnish VMSS to App Gateway backend pool

**Files:**
- Modify: `compute.tf:38-48` (ip_configuration block inside network_interface)

**Context:** The App Gateway defines a named `backend_address_pool` but the Varnish VMSS NIC has no reference to it. Traffic entering the gateway has zero backends — the site is completely unreachable.

**Step 1: Edit the ip_configuration block in compute.tf**

In `compute.tf`, replace the `ip_configuration` block inside `network_interface`:

```hcl
    ip_configuration {
      name      = "primary"
      primary   = true
      subnet_id = azurerm_subnet.compute.id
    }
```

with:

```hcl
    ip_configuration {
      name      = "primary"
      primary   = true
      subnet_id = azurerm_subnet.compute.id
      application_gateway_backend_address_pool_ids = each.key == "varnish" ? [
        one([for pool in azurerm_application_gateway.this.backend_address_pool
             : pool.id if pool.name == local.appgw_backend_pool_name])
      ] : null
    }
```

**Step 2: Validate**

```bash
terraform validate
```

Expected: `Success! The configuration is valid.`

**Step 3: Format check**

```bash
terraform fmt -check
```

If it exits non-zero, run `terraform fmt` then re-check.

**Step 4: Commit**

```bash
git add compute.tf
git commit -m "fix: wire varnish VMSS to App Gateway backend pool"
```

---

### Task 2: Add OpenSearch NSG rule and remove orphaned imgproxy rule

**Files:**
- Modify: `security_groups.tf`

**Context:** The data-subnet NSG allows only MySQL (3306) and Redis (6379) then denies everything, so the OpenSearch VM on that subnet is unreachable on port 9200. Separately, the compute NSG allows port 8080 for imgproxy — a service that doesn't exist in this codebase. Both need fixing in one commit.

**Step 1: Add OpenSearch rule to the data NSG**

In `security_groups.tf`, in `azurerm_network_security_group.data`, after the `allow-redis-from-compute` rule (priority 110) and before the `deny-all-inbound` rule (priority 200), add:

```hcl
  security_rule {
    name                       = "allow-opensearch-from-compute"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "9200"
    source_address_prefix      = azurerm_subnet.compute.address_prefixes[0]
    destination_address_prefix = "*"
  }
```

**Step 2: Remove the orphaned imgproxy rule from the compute NSG**

In `security_groups.tf`, in `azurerm_network_security_group.compute`, delete the entire `allow-imgproxy-from-gateway` security_rule block (priority 110, port 8080). There is no imgproxy resource in this codebase.

**Step 3: Validate and commit**

```bash
terraform validate && terraform fmt -check
git add security_groups.tf
git commit -m "fix: add OpenSearch NSG rule, remove orphaned imgproxy rule"
```

---

### Task 3: Fix apex DNS to route through Front Door; add www custom domain

**Files:**
- Modify: `dns.tf`
- Modify: `cdn.tf`

**Context:** `dns.tf` has an A record at `@` pointing directly to the App Gateway public IP, bypassing Front Door's CDN, caching, and geo-blocking for bare-domain traffic. Additionally, `www.` is only a CNAME to the Front Door endpoint hostname — not a registered custom domain — so HTTPS for `www.` uses the wildcard `*.azurefd.net` certificate rather than a domain-validated cert.

**Step 1: Replace the apex A record with an alias to Front Door**

In `dns.tf`, replace:

```hcl
resource "azurerm_dns_a_record" "appgw" {
  name                = "@"
  zone_name           = azurerm_dns_zone.public.name
  resource_group_name = azurerm_resource_group.this.name
  ttl                 = 300
  records             = [azurerm_public_ip.appgw.ip_address]
}
```

with:

```hcl
resource "azurerm_dns_a_record" "appgw" {
  name                = "@"
  zone_name           = azurerm_dns_zone.public.name
  resource_group_name = azurerm_resource_group.this.name
  ttl                 = 300
  target_resource_id  = azurerm_cdn_frontdoor_endpoint.this.id
}
```

**Step 2: Add www as a Front Door custom domain in cdn.tf**

In `cdn.tf`, after `azurerm_cdn_frontdoor_custom_domain.this`, add:

```hcl
resource "azurerm_cdn_frontdoor_custom_domain" "www" {
  name                     = "${local.project}-www-domain"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.this.id
  host_name                = "www.${local.env.domain}"

  tls {
    certificate_type = "ManagedCertificate"
  }
}

resource "azurerm_cdn_frontdoor_custom_domain_association" "www" {
  cdn_frontdoor_custom_domain_id = azurerm_cdn_frontdoor_custom_domain.www.id
  cdn_frontdoor_route_ids        = [azurerm_cdn_frontdoor_route.this.id]
}
```

**Step 3: Add www to the Front Door route's custom domain list in cdn.tf**

In `azurerm_cdn_frontdoor_route.this`, change:

```hcl
  cdn_frontdoor_custom_domain_ids = [azurerm_cdn_frontdoor_custom_domain.this.id]
```

to:

```hcl
  cdn_frontdoor_custom_domain_ids = [
    azurerm_cdn_frontdoor_custom_domain.this.id,
    azurerm_cdn_frontdoor_custom_domain.www.id,
  ]
```

**Step 4: Add the www Front Door TXT validation record in dns.tf**

In `dns.tf`, after `azurerm_dns_txt_record.frontdoor_validation`, add:

```hcl
resource "azurerm_dns_txt_record" "frontdoor_validation_www" {
  name                = "_dnsauth.www"
  zone_name           = azurerm_dns_zone.public.name
  resource_group_name = azurerm_resource_group.this.name
  ttl                 = 300

  record {
    value = azurerm_cdn_frontdoor_custom_domain.www.validation_token
  }
}
```

**Step 5: Validate and commit**

```bash
terraform validate && terraform fmt -check
git add dns.tf cdn.tf
git commit -m "fix: apex DNS alias to Front Door, add www as custom domain with managed TLS"
```

---

### Task 4: Add MySQL delegation subnet and Bastion subnet to VNet

**Files:**
- Modify: `vpc_network.tf`

**Context:** MySQL Flexible Server VNet integration (Task 6) requires a dedicated delegated subnet. Azure Bastion (Task 5) requires a subnet named exactly `AzureBastionSubnet`. Both are added here so downstream tasks have their subnets ready. Current subnets use indices 0–2; we add at indices 3 and 4.

**Step 1: Add the MySQL delegation subnet**

In `vpc_network.tf`, after `azurerm_subnet.gateway`, add:

```hcl
resource "azurerm_subnet" "mysql" {
  name                 = "${local.project}-mysql-subnet"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [cidrsubnet(local.env.vnet.cidr_block, 4, 3)]

  delegation {
    name = "mysql-delegation"
    service_delegation {
      name    = "Microsoft.DBforMySQL/flexibleServers"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}
```

**Step 2: Add the Bastion subnet**

In `vpc_network.tf`, after the mysql subnet, add:

```hcl
resource "azurerm_subnet" "bastion" {
  name                 = "AzureBastionSubnet"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [cidrsubnet(local.env.vnet.cidr_block, 4, 4)]
}
```

**Step 3: Validate and commit**

```bash
terraform validate && terraform fmt -check
git add vpc_network.tf
git commit -m "feat: add MySQL delegation subnet and AzureBastionSubnet"
```

---

### Task 5: Add Azure Bastion host

**Files:**
- Create: `bastion.tf`

**Context:** SSH is blocked by NSG (correct for hardened compute), but there is no management access path. Azure Bastion provides browser-based SSH/RDP over HTTPS without opening port 22, using the `AzureBastionSubnet` added in Task 4.

**Step 1: Create bastion.tf**

```hcl


///////////////////////////////////////////////////////////[ AZURE BASTION ]//////////////////////////////////////////////////

resource "azurerm_public_ip" "bastion" {
  name                = "${local.project}-bastion-pip"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.default_tags
}

resource "azurerm_bastion_host" "this" {
  name                = "${local.project}-bastion"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  tags                = local.default_tags

  ip_configuration {
    name                 = "bastion-ip-config"
    subnet_id            = azurerm_subnet.bastion.id
    public_ip_address_id = azurerm_public_ip.bastion.id
  }
}
```

**Step 2: Validate and commit**

```bash
terraform validate && terraform fmt -check
git add bastion.tf
git commit -m "feat: add Azure Bastion for SSH access without opening port 22"
```

---

### Task 6: MySQL VNet integration (private, no public endpoint)

**Files:**
- Modify: `database.tf`

**Context:** MySQL Flexible Server currently has no `delegated_subnet_id` or `private_dns_zone_id`, meaning it has a public FQDN and is reachable over the internet. With VNet integration, the server is only accessible from within the VNet via the private DNS zone. Requires the `azurerm_subnet.mysql` from Task 4 and `azurerm_private_dns_zone_virtual_network_link.this` from `service_discovery.tf`.

**WARNING for existing deployments:** Adding VNet integration to an existing MySQL Flexible Server forces a resource replacement (destroy + create). On a fresh deploy, this is a no-op concern.

**Step 1: Add delegated_subnet_id, private_dns_zone_id, and depends_on to the MySQL server**

In `database.tf`, inside `azurerm_mysql_flexible_server.this`, add these three lines after `geo_redundant_backup_enabled`:

```hcl
  delegated_subnet_id          = azurerm_subnet.mysql.id
  private_dns_zone_id          = azurerm_private_dns_zone.internal.id
```

And add a `depends_on` block before the closing brace:

```hcl
  depends_on = [azurerm_private_dns_zone_virtual_network_link.this]
```

The full resource should look like:

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
  geo_redundant_backup_enabled = false
  delegated_subnet_id          = azurerm_subnet.mysql.id
  private_dns_zone_id          = azurerm_private_dns_zone.internal.id

  high_availability {
    mode = local.env.mysql.high_availability ? "ZoneRedundant" : "Disabled"
  }

  storage {
    size_gb           = local.env.mysql.storage_gb
    auto_grow_enabled = true
  }

  tags       = local.default_tags
  depends_on = [azurerm_private_dns_zone_virtual_network_link.this]
}
```

**Step 2: Validate and commit**

```bash
terraform validate && terraform fmt -check
git add database.tf
git commit -m "fix: MySQL VNet integration — move to private subnet, remove public endpoint"
```

---

### Task 7: Key Vault purge protection — enable for non-developer environments

**Files:**
- Modify: `secrets.tf`

**Context:** `purge_protection_enabled = false` combined with `purge_soft_delete_on_destroy = true` (in provider.tf) means a `terraform destroy` permanently deletes secrets with no recovery window. In staging/production this is dangerous. We enable it conditionally so developer workspaces can still be torn down cleanly.

**Step 1: Change purge_protection_enabled to a conditional**

In `secrets.tf`, in `azurerm_key_vault.this`, replace:

```hcl
  purge_protection_enabled = false
```

with:

```hcl
  purge_protection_enabled = local.environment != "developer"
```

**Step 2: Validate and commit**

```bash
terraform validate && terraform fmt -check
git add secrets.tf
git commit -m "fix: enable Key Vault purge protection in staging and production"
```

---

### Task 8: Remote state backend template

**Files:**
- Create: `backend.tf.example`

**Context:** There is no `backend` block — state is local. Committed `terraform.tfstate` would expose secrets; different operators running `apply` from different machines would have divergent state. We provide a ready-to-use Azure Blob Storage backend template. Users copy it to `backend.tf` (gitignored) and fill in their storage account details.

**Step 1: Verify .gitignore covers backend.tf**

```bash
grep "backend.tf" /Users/safoor/Code/easecloud-opensource/magento2-azure-terraform/.gitignore
```

If there is no match, add `backend.tf` to `.gitignore`.

**Step 2: Create backend.tf.example**

```hcl
# Copy this file to backend.tf and fill in your storage account details.
# Create the storage account and container before running terraform init:
#
#   az group create -n tfstate-rg -l eastus
#   az storage account create -n <unique-name> -g tfstate-rg --sku Standard_LRS
#   az storage container create -n tfstate --account-name <unique-name>
#
# Then run: terraform init -reconfigure

terraform {
  backend "azurerm" {
    resource_group_name  = "tfstate-rg"
    storage_account_name = "<your-tfstate-storage-account>"
    container_name       = "tfstate"
    key                  = "magento2-azure.tfstate"
  }
}
```

**Step 3: Commit**

```bash
git add backend.tf.example .gitignore
git commit -m "docs: add remote state backend template (backend.tf.example)"
```

---

### Task 9: Externalize OpenSearch VM config; clean up unused YAML keys

**Files:**
- Modify: `developer.config.yaml`
- Modify: `search.tf`

**Context:** The OpenSearch VM in `search.tf` hardcodes `Standard_D2ps_v5`, disk size 50 GB, and OpenSearch version `2.17.0`. Meanwhile, `developer.config.yaml` has a `search` block with `sku`, `replica_count`, `partition_count` — leftovers from an earlier Azure AI Search design that was replaced by the self-hosted OpenSearch VM. Those keys are never read. We remove the dead config and replace it with an `opensearch` block.

**Step 1: Update developer.config.yaml**

Replace the `search` block:

```yaml
search:
  sku: "standard"
  replica_count: 1
  partition_count: 1
```

with:

```yaml
opensearch:
  vm_size: "Standard_D2ps_v5"
  disk_size_gb: 50
  version: "2.17.0"
```

**Step 2: Update search.tf to use config values**

In `search.tf`, in `azurerm_linux_virtual_machine.opensearch`:

Replace `size = "Standard_D2ps_v5"` with:
```hcl
  size = local.env.opensearch.vm_size
```

Replace `disk_size_gb = 50` in the `os_disk` block with:
```hcl
      disk_size_gb         = local.env.opensearch.disk_size_gb
```

Replace the hardcoded version in the `custom_data` heredoc:
```
    curl -fsSL https://artifacts.opensearch.org/releases/bundle/opensearch/2.x/opensearch-2.17.0-linux-arm64.tar.gz \
```
with:
```hcl
    curl -fsSL https://artifacts.opensearch.org/releases/bundle/opensearch/2.x/opensearch-${local.env.opensearch.version}-linux-arm64.tar.gz \
```

Note: the heredoc is inside `base64encode(<<-EOT ... EOT)`. To interpolate a Terraform local inside a heredoc, use `${local.env.opensearch.version}` directly (this is a Terraform templatefile-style heredoc, not a shell heredoc, so `${}` is Terraform interpolation, while `$${}` is a literal `${}`).

**Step 3: Validate and commit**

```bash
terraform validate && terraform fmt -check
git add developer.config.yaml search.tf
git commit -m "fix: externalize OpenSearch VM config, remove dead Azure AI Search yaml keys"
```

---

### Task 10: Storage account name length guard

**Files:**
- Modify: `storage.tf`
- Modify: `filesystem.tf`

**Context:** Azure storage account names have a 24-character maximum. The current pattern `${replace(local.project, "-", "")}sa` can silently exceed the limit for longer brand+codename combinations. Add `substr` guards matching the pattern already used for Key Vault names in `secrets.tf`.

**Step 1: Fix storage.tf**

In `azurerm_storage_account.this`, replace:

```hcl
  name = "${replace(local.project, "-", "")}sa"
```

with:

```hcl
  name = "${substr(replace(local.project, "-", ""), 0, 22)}sa"
```

**Step 2: Fix filesystem.tf**

In `azurerm_storage_account.nfs`, replace:

```hcl
  name = "${replace(local.project, "-", "")}nfssa"
```

with:

```hcl
  name = "${substr(replace(local.project, "-", ""), 0, 19)}nfssa"
```

(19 + 5 = 24, the Azure maximum.)

**Step 3: Validate and commit**

```bash
terraform validate && terraform fmt -check
git add storage.tf filesystem.tf
git commit -m "fix: guard storage account names at 24-char Azure maximum"
```

---

### Task 11: Workspace validation with a clear error message

**Files:**
- Modify: `locals.tf` (add validation resource)
- Or create: `validation.tf`

**Context:** If a user runs `terraform plan` from the default workspace or a misnamed workspace, Terraform will try `yamldecode("")` and emit a confusing "Invalid YAML" error. We replace that with a clear message pointing to the fix.

**Step 1: Add a terraform_data precondition block**

Add this to `locals.tf` (it is a resource, but keeping it with the env config is logical):

```hcl
resource "terraform_data" "workspace_validation" {
  lifecycle {
    precondition {
      condition     = contains(["developer", "staging", "production"], local.environment)
      error_message = "Terraform workspace must be 'developer', 'staging', or 'production'. Got: '${local.environment}'. Run: terraform workspace new developer"
    }
  }
}
```

**Step 2: Validate and commit**

```bash
terraform validate && terraform fmt -check
git add locals.tf
git commit -m "feat: add workspace validation with actionable error message"
```

---

## Summary of changes

| Task | File(s) | Type |
|---|---|---|
| 1 | `compute.tf` | Critical fix |
| 2 | `security_groups.tf` | Critical fix |
| 3 | `dns.tf`, `cdn.tf` | Critical fix |
| 4 | `vpc_network.tf` | Infrastructure addition |
| 5 | `bastion.tf` (new) | Infrastructure addition |
| 6 | `database.tf` | Security hardening |
| 7 | `secrets.tf` | Security hardening |
| 8 | `backend.tf.example` (new) | Operational tooling |
| 9 | `developer.config.yaml`, `search.tf` | Cleanup |
| 10 | `storage.tf`, `filesystem.tf` | Defensive fix |
| 11 | `locals.tf` | DX improvement |
