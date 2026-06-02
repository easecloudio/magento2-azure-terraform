# Magento 2 Azure Terraform

Terraform module for provisioning a production-grade Magento 2 infrastructure on Microsoft Azure, including VMSS, Azure Database for MySQL, Azure Cache for Redis, Azure Cognitive Search, Service Bus, Blob Storage, Azure Files, Front Door with WAF, and cost budgets.

## Prerequisites

- Terraform >= 1.9
- Azure CLI or service principal credentials

### Authentication

**Local development** — authenticate with the Azure CLI:

```bash
az login
az account set --subscription "<your-subscription-id>"
```

**CI / automated pipelines** — set the following environment variables:

| Variable | Description |
|---|---|
| `ARM_CLIENT_ID` | Service principal application (client) ID |
| `ARM_CLIENT_SECRET` | Service principal client secret |
| `ARM_SUBSCRIPTION_ID` | Target Azure subscription ID |
| `ARM_TENANT_ID` | Azure Active Directory tenant ID |

## Usage

1. Copy `developer.config.yaml` and fill in your values.
2. Initialize Terraform:

   ```bash
   terraform init
   terraform workspace select developer
   ```

3. Plan and apply:

   ```bash
   terraform plan
   terraform apply
   ```

For staging and production environments, create the corresponding `staging.config.yaml` or `production.config.yaml` and switch workspaces accordingly.
