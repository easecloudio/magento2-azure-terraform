# Magento 2 Azure Terraform

Deploy a production-ready, auto-scaling Magento 2 infrastructure on Microsoft Azure using Terraform and Ampere-based VMSS instances.

## Overview

This project provisions a complete Magento 2 infrastructure on Azure including:

- **Virtual Machine Scale Sets** — frontend (PHP-FPM + Nginx) and varnish tiers on ARM-based Dpdsv5 instances
- **Azure Database for MySQL Flexible Server** — managed relational database with configurable parameters and optional high availability
- **Azure Cache for Redis** — session and full-page cache instances
- **Azure Cognitive Search** — Magento catalog search
- **Azure Service Bus** — async message queue
- **Azure Application Gateway** — with Azure WAF, SSL termination, and geo-blocking
- **Azure Front Door** — CDN with global edge acceleration
- **Azure Files (NFS)** — shared `var/` and `media/` mounts across all VMs
- **Azure Blob Storage** — media, optimized media, system files, and backups
- **Azure Event Grid** — release deployment triggered by Blob Storage uploads
- **Azure Private DNS** — internal service discovery

All configuration is driven by a single YAML file per environment (`developer.config.yaml`, `staging.config.yaml`, `production.config.yaml`). No `.tfvars` files needed.

## Architecture

```
Internet
   │
   ▼
Azure WAF (Application Gateway WAF)
   │
   ▼
Azure Application Gateway
   │
   ├──▶ Varnish VMSS (cache layer)
   │         │
   └──▶ Frontend VMSS (Nginx + PHP-FPM)
              │
              ├──▶ MySQL Flexible Server
              ├──▶ Azure Cache for Redis (session + cache)
              ├──▶ Azure Cognitive Search
              ├──▶ Azure Files NFS (var/ + media/)
              └──▶ Blob Storage (media + system)
```

## Prerequisites

- Terraform >= 1.9
- Azure CLI (`az`) installed and authenticated
- An Azure subscription with sufficient quota for VMSS, MySQL Flexible, Redis Premium, and Cognitive Search

### Authentication

**Local development** — authenticate with the Azure CLI:

```bash
az login
az account set --subscription "<your-subscription-id>"
```

**CI/automated pipelines** — set the following environment variables:

| Variable | Description |
|---|---|
| `ARM_CLIENT_ID` | Service principal application (client) ID |
| `ARM_CLIENT_SECRET` | Service principal client secret |
| `ARM_SUBSCRIPTION_ID` | Target Azure subscription ID |
| `ARM_TENANT_ID` | Azure Active Directory tenant ID |

## Quick Start

```bash
# 1. Clone the repository
git clone https://github.com/easecloud/magento2-azure-terraform.git
cd magento2-azure-terraform

# 2. Copy and edit your environment config
cp developer.config.yaml developer.config.yaml
# Edit developer.config.yaml: set brand, domain, admin_email, azure.subscription_id, azure.resource_group, ssh_public_key, etc.

# 3. Initialize Terraform
terraform init

# 4. Create a workspace matching your config file name
terraform workspace new developer

# 5. Plan and apply
terraform plan -out developer.plan
terraform apply developer.plan
```

## Configuration Reference

All environment settings live in `<workspace>.config.yaml`. Copy `developer.config.yaml` as a starting point:

| Key | Description |
|-----|-------------|
| `brand` | Short brand identifier — used in all resource names |
| `codename` | Project codename — combined with brand as `brand-codename` |
| `github_repo` | Source repository reference (used in tags and automation) |
| `domain` | Primary domain name for DNS and SSL |
| `admin_email` | Email for budget alerts and notifications |
| `azure.subscription_id` | Target Azure subscription ID |
| `azure.location` | Azure region (e.g. `eastus`) |
| `azure.resource_group` | Name of the Azure resource group to create or reuse |
| `vnet.cidr_block` | VNet IP range (e.g. `172.35.0.0/16`) |
| `vnet.availability_zones_qty` | Number of availability zones to distribute resources across |
| `ssh_public_key` | SSH public key added to VM instances for emergency access |
| `vmss.frontend.vm_size` | Azure VM size for frontend instances (e.g. `Standard_D4ps_v5`) |
| `vmss.frontend.os_disk_size_gb` | OS disk size in GB for frontend VMs |
| `vmss.frontend.desired_capacity` | Target number of frontend instances |
| `vmss.frontend.min_count` | Minimum instance count |
| `vmss.frontend.max_count` | Maximum instance count |
| `vmss.varnish.vm_size` | Azure VM size for varnish instances (e.g. `Standard_D2ps_v5`) |
| `vmss.varnish.os_disk_size_gb` | OS disk size in GB for varnish VMs |
| `vmss.varnish.desired_capacity` | Target number of varnish instances |
| `vmss.varnish.min_count` | Minimum instance count |
| `vmss.varnish.max_count` | Maximum instance count |
| `autoscale.cooldown_minutes` | Minutes to wait between scaling actions |
| `autoscale.out_threshold_percent` | CPU % that triggers scale-out |
| `autoscale.in_threshold_percent` | CPU % that triggers scale-in |
| `mysql.sku` | MySQL Flexible Server SKU (e.g. `GP_Standard_D2ds_v4`) |
| `mysql.storage_gb` | Initial data storage in GB |
| `mysql.backup_retention_days` | Number of days to retain automated backups |
| `mysql.engine_version` | MySQL engine version (e.g. `8.0.21`) |
| `mysql.admin_login` | Database administrator username |
| `mysql.high_availability` | Enable zone-redundant high availability (`true`/`false`) |
| `mysql.parameters` | List of `{name, value}` MySQL server parameter overrides |
| `redis.sku` | Azure Cache for Redis tier (e.g. `Premium`) |
| `redis.family` | Redis family matching the SKU (e.g. `P`) |
| `redis.capacity` | Redis cache size in the chosen family |
| `redis.name` | List of cache instance names to create (e.g. `session`, `cache`) |
| `search.sku` | Azure Cognitive Search pricing tier (e.g. `standard`) |
| `search.replica_count` | Number of search replicas for high availability |
| `search.partition_count` | Number of search partitions for horizontal scaling |
| `service_bus.sku` | Azure Service Bus tier (`Basic`, `Standard`, or `Premium`) |
| `blob_storage.containers` | List of blob container names (media, media-optimized, system, backup) |
| `azure_files.shares.var.quota_gb` | Storage quota in GB for the `var/` NFS file share |
| `azure_files.shares.media.quota_gb` | Storage quota in GB for the `media/` NFS file share |
| `waf.restricted_countries` | List of ISO 3166-1 alpha-2 country codes to block at WAF |
| `password` | List of secret names to generate and store as passwords |
| `string` | List of secret names to store as plain strings |
| `budget.amount` | Monthly budget limit in USD |
| `budget.threshold_percent` | Alert threshold as a percentage of the budget |

## Workspaces

Terraform workspaces map directly to config files:

| Workspace | Config file |
|-----------|-------------|
| `developer` | `developer.config.yaml` |
| `staging` | `staging.config.yaml` |
| `production` | `production.config.yaml` |

Switch workspaces with `terraform workspace select <name>`.

## No-SSH Access

Instances have an SSH public key provisioned but direct SSH is not the primary management path. Prefer the following Azure-native methods:

**Azure Bastion** — connect to a VM's private IP through a browser-based SSH session without opening port 22 to the internet:

```bash
az network bastion ssh \
  --name <bastion-name> \
  --resource-group <resource-group> \
  --target-resource-id <vm-resource-id> \
  --auth-type ssh-key \
  --username azureuser \
  --ssh-key ~/.ssh/id_rsa
```

**az vm run-command** — execute a command on a VM directly from the CLI without any network path:

```bash
az vm run-command invoke \
  --resource-group <resource-group> \
  --name <vm-name> \
  --command-id RunShellScript \
  --scripts "systemctl status nginx"
```

For VMSS instances, use `az vmss run-command invoke` and specify `--instance-id`.

## Release Deployment

Releases are deployed by uploading a versioned zip archive to the `system` Blob Storage container under a `release/` prefix. An Azure Event Grid subscription watches for `Microsoft.Storage.BlobCreated` events matching that prefix and delivers them to an Azure Function or Logic App, which triggers each VMSS instance to download the artifact and run the deployment process. The Event Grid webhook URL is configured outside Terraform in the `events.tf` placeholder.

## Security

- Credentials generated as random secrets and stored in Azure Key Vault
- WAF rules on Application Gateway: geo-blocking, OWASP managed rule set, rate limiting
- Network security groups scoped per service tier; backend resources accessible only from the VMSS subnets
- Blob Storage containers are private; media delivery uses SAS tokens or Front Door origin access

## License

Apache 2.0 — see [LICENSE](LICENSE)
