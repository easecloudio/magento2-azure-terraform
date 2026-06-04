# Cron and Admin VMSS Pools Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add dedicated `admin` and `cron` VMSS pools so Magento admin traffic and cron jobs are isolated from the storefront compute tier.

**Architecture:** The existing `for_each = local.env.vmss` pattern in `compute.tf` picks up new YAML keys automatically. The App Gateway `frontend-direct-pool` is renamed to `admin-pool` and rewired to the new `admin` VMSS. The `cron` VMSS has no App Gateway association and gets a systemd timer for `php bin/magento cron:run`. The `frontend` VMSS is disconnected from the App Gateway backend (it only receives traffic from Varnish internally).

**Tech Stack:** Terraform >= 1.9, azurerm ~> 4.0, Debian 12 ARM64

---

### Task 1: Add admin and cron pools to developer.config.yaml

**Files:**
- Modify: `developer.config.yaml`

**Context:** The `vmss` block is the source of truth for all VMSS pools. Adding keys here causes `compute.tf` (via `for_each = local.env.vmss`) to automatically create the VMSS, autoscale settings, and monitoring. Admin: 1–2 instances (small, admin users are few). Cron: exactly 1 instance (min=max=desired=1 prevents duplicate cron runs).

**Step 1: Add admin and cron under the vmss block**

In `developer.config.yaml`, after `vmss.varnish`, add:

```yaml
  admin:
    vm_size: "Standard_D2ps_v5"
    os_disk_size_gb: 50
    desired_capacity: 1
    min_count: 1
    max_count: 2
  cron:
    vm_size: "Standard_D2ps_v5"
    os_disk_size_gb: 50
    desired_capacity: 1
    min_count: 1
    max_count: 1
```

**Step 2: Validate**

```bash
cd /Users/safoor/Code/easecloud-opensource/magento2-azure-terraform
terraform validate
```

Expected: pre-existing SSH key errors only. `terraform fmt -check` — run `terraform fmt` if needed.

**Step 3: Commit**

```bash
git add developer.config.yaml
git commit -m "feat: add admin and cron VMSS pool config"
git push origin main
```

---

### Task 2: Rename frontend-direct locals to admin in locals.tf

**Files:**
- Modify: `locals.tf`

**Context:** The five locals added during the admin bypass PR use `frontend` in their names (`appgw_frontend_backend_pool_name`, etc.). Now that a proper `admin` VMSS exists, these should be named `admin` for clarity. The Azure resource name also changes from `*-frontend-pool` to `*-admin-pool`.

**Step 1: Read locals.tf to confirm current state**

The five locals to rename are:
```
appgw_frontend_backend_pool_name  → appgw_admin_backend_pool_name
appgw_frontend_http_settings_name → appgw_admin_http_settings_name
appgw_frontend_probe_name         → appgw_admin_probe_name
```

(Keep `appgw_url_path_map_name` and `appgw_admin_path_rule_name` unchanged.)

**Step 2: Apply renames and update string values**

Replace the three locals:

```hcl
  appgw_admin_backend_pool_name  = "${local.project}-admin-pool"
  appgw_admin_http_settings_name = "${local.project}-admin-settings"
  appgw_admin_probe_name         = "${local.project}-admin-probe"
```

**Step 3: Validate, commit**

```bash
terraform validate
terraform fmt -check || terraform fmt
git add locals.tf
git commit -m "refactor: rename frontend-direct App Gateway locals to admin"
git push origin main
```

---

### Task 3: Update load_balancer.tf to use renamed admin locals

**Files:**
- Modify: `load_balancer.tf`

**Context:** `load_balancer.tf` references the three renamed locals. Every occurrence of `local.appgw_frontend_*` must be updated to `local.appgw_admin_*`. This is a find-and-replace — no structural changes to the resource definitions.

**Step 1: Read load_balancer.tf fully to find all occurrences**

There will be references in:
- `azurerm_web_application_firewall_policy.this` (AdminIPRestriction custom rule does not use these locals — skip)
- `azurerm_application_gateway.this`: backend_address_pool name, backend_http_settings name, probe name, url_path_map path_rule

**Step 2: Replace all three local references**

Use replace_all for each:
- `local.appgw_frontend_backend_pool_name` → `local.appgw_admin_backend_pool_name`
- `local.appgw_frontend_http_settings_name` → `local.appgw_admin_http_settings_name`
- `local.appgw_frontend_probe_name` → `local.appgw_admin_probe_name`

**Step 3: Validate, commit**

```bash
terraform validate
terraform fmt -check || terraform fmt
git add load_balancer.tf
git commit -m "refactor: update App Gateway to use admin-pool naming"
git push origin main
```

---

### Task 4: Create cloud-init/admin.sh and cloud-init/cron.sh

**Files:**
- Create: `cloud-init/admin.sh`
- Create: `cloud-init/cron.sh`

**Context:** `compute.tf` uses `templatefile("${path.module}/cloud-init/${each.key}.sh", ...)` — so files named `admin.sh` and `cron.sh` must exist before `terraform validate` can resolve the template paths at plan time. Admin bootstrap is identical to frontend (installs Azure CLI + Ansible for Ansible-based provisioning). Cron bootstrap additionally installs a systemd timer that runs `php bin/magento cron:run` every minute.

**Step 1: Create cloud-init/admin.sh**

```bash
#!/bin/bash
set -euo pipefail

BRAND="${brand}"
PROJECT="${project}"
ENVIRONMENT="${environment}"
LOCATION="${location}"

hostnamectl set-hostname "admin.$${BRAND}.internal"
echo "127.0.0.1 admin.$${BRAND}.internal" >> /etc/hosts

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq curl jq unzip python3-pip python3-venv

curl -sL https://aka.ms/InstallAzureCLIDeb | bash

pip3 install pipx --quiet
pipx install ansible-core
pipx ensurepath

echo "Admin instance initialized: $PROJECT/$ENVIRONMENT" >> /var/log/cloud-init-custom.log
```

**Step 2: Create cloud-init/cron.sh**

```bash
#!/bin/bash
set -euo pipefail

BRAND="${brand}"
PROJECT="${project}"
ENVIRONMENT="${environment}"
LOCATION="${location}"

hostnamectl set-hostname "cron.$${BRAND}.internal"
echo "127.0.0.1 cron.$${BRAND}.internal" >> /etc/hosts

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq curl jq unzip python3-pip python3-venv

curl -sL https://aka.ms/InstallAzureCLIDeb | bash

pip3 install pipx --quiet
pipx install ansible-core
pipx ensurepath

# Systemd timer — runs Magento cron every minute after Ansible deploys the app
cat > /etc/systemd/system/magento-cron.service <<'UNIT'
[Unit]
Description=Magento 2 Cron
After=network.target

[Service]
Type=oneshot
User=www-data
WorkingDirectory=/var/www/html
ExecStart=/usr/bin/php bin/magento cron:run
StandardOutput=journal
StandardError=journal
UNIT

cat > /etc/systemd/system/magento-cron.timer <<'UNIT'
[Unit]
Description=Run Magento 2 cron every minute

[Timer]
OnBootSec=5min
OnUnitActiveSec=1min
Unit=magento-cron.service

[Install]
WantedBy=timers.target
UNIT

systemctl daemon-reload
systemctl enable magento-cron.timer

echo "Cron instance initialized: $PROJECT/$ENVIRONMENT" >> /var/log/cloud-init-custom.log
```

**Step 3: Validate, commit**

```bash
terraform validate
terraform fmt -check || terraform fmt
git add cloud-init/admin.sh cloud-init/cron.sh
git commit -m "feat: add admin and cron cloud-init bootstrap scripts"
git push origin main
```

---

### Task 5: Update compute.tf — rewire backend pools and skip health extension for cron

**Files:**
- Modify: `compute.tf`

**Context:** Three changes:

1. **Backend pool wiring** — current logic: `varnish → storefront pool`, `frontend → admin pool`, everything else → null. New logic: `varnish → storefront pool`, `admin → admin pool`, everything else (frontend, cron) → null. The `frontend` VMSS only receives traffic from Varnish over the internal compute subnet — it has no App Gateway backend pool association.

2. **Health extension** — the `ApplicationHealthLinux` extension checks HTTP port 80. The `cron` VMSS runs no web server, so the health check would always fail. Wrap the `extension` block in a `dynamic` and skip it for `cron`.

3. **Rolling upgrade for cron** — `upgrade_mode = "Rolling"` requires a health source. For cron (always 1 instance), use `"Automatic"` instead.

**Step 1: Read compute.tf fully**

Confirm the current `application_gateway_backend_address_pool_ids` expression, the static `extension` block, and the `upgrade_mode` line.

**Step 2: Update the backend pool expression**

Find the current `application_gateway_backend_address_pool_ids` block (currently references `each.key == "varnish"` and `each.key == "frontend"`). Replace with:

```hcl
      application_gateway_backend_address_pool_ids = each.key == "varnish" ? [
        one([for pool in azurerm_application_gateway.this.backend_address_pool
             : pool.id if pool.name == local.appgw_backend_pool_name])
        ] : each.key == "admin" ? [
        one([for pool in azurerm_application_gateway.this.backend_address_pool
             : pool.id if pool.name == local.appgw_admin_backend_pool_name])
      ] : null
```

**Step 3: Make upgrade_mode conditional for cron**

Replace the static line:
```hcl
  upgrade_mode        = "Rolling"
```
with:
```hcl
  upgrade_mode        = each.key == "cron" ? "Automatic" : "Rolling"
```

**Step 4: Convert the static extension block to dynamic, skip for cron**

Replace the static `extension { ... }` block with:

```hcl
  dynamic "extension" {
    for_each = each.key != "cron" ? [1] : []
    content {
      name                 = "HealthExtension"
      publisher            = "Microsoft.ManagedServices"
      type                 = "ApplicationHealthLinux"
      type_handler_version = "1.0"

      settings = jsonencode({
        protocol    = "http"
        port        = 80
        requestPath = "/"
      })
    }
  }
```

**Step 5: Validate, commit**

```bash
terraform validate
terraform fmt -check || terraform fmt
git add compute.tf
git commit -m "feat: admin and cron VMSS — rewire backend pools, skip health extension for cron"
git push origin main
```

---

### Task 6: Add admin VMSS CPU alert to monitoring.tf

**Files:**
- Modify: `monitoring.tf`

**Context:** The existing CPU alerts for `frontend` and `varnish` are hardcoded resources. Add a matching alert for `admin`. Cron is intentionally omitted — CPU spikes on cron are expected behaviour (indexing, email queues) and should not page on-call.

**Step 1: Add the admin CPU alert**

After `azurerm_monitor_metric_alert.cpu_high_varnish`, add:

```hcl
resource "azurerm_monitor_metric_alert" "cpu_high_admin" {
  name                = "${local.project}-admin-cpu-high"
  resource_group_name = azurerm_resource_group.this.name
  scopes              = [azurerm_linux_virtual_machine_scale_set.this["admin"].id]
  description         = "Alert when admin VMSS CPU exceeds 85%"
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"
  tags                = local.default_tags

  criteria {
    metric_namespace = "Microsoft.Compute/virtualMachineScaleSets"
    metric_name      = "Percentage CPU"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 85
  }

  action {
    action_group_id = azurerm_monitor_action_group.default.id
  }
}
```

**Step 2: Validate, commit**

```bash
terraform validate
terraform fmt -check || terraform fmt
git add monitoring.tf
git commit -m "feat: add admin VMSS CPU alert to Azure Monitor"
git push origin main
```

---

## Summary

| Task | Files | Change |
|---|---|---|
| 1 | `developer.config.yaml` | Add `admin` (1–2 instances) and `cron` (fixed 1 instance) VMSS pools |
| 2 | `locals.tf` | Rename `appgw_frontend_*` → `appgw_admin_*` |
| 3 | `load_balancer.tf` | Update all local references to match renamed locals |
| 4 | `cloud-init/admin.sh`, `cloud-init/cron.sh` | Bootstrap scripts (admin = same as frontend; cron adds systemd timer) |
| 5 | `compute.tf` | Rewire backend pools; `admin` → admin-pool, `frontend`/`cron` → null; dynamic health extension; Automatic upgrade for cron |
| 6 | `monitoring.tf` | Admin CPU > 85% alert |
