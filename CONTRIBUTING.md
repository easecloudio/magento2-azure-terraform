# Contributing to magento2-azure-terraform

Thank you for taking the time to contribute. This document covers everything you need to get started.

## Table of contents

- [Ways to contribute](#ways-to-contribute)
- [Reporting issues](#reporting-issues)
- [Development setup](#development-setup)
- [Making changes](#making-changes)
- [Commit conventions](#commit-conventions)
- [Pull request process](#pull-request-process)
- [Code style](#code-style)
- [Adding a new environment config](#adding-a-new-environment-config)
- [Adding a new Azure service](#adding-a-new-azure-service)
- [Testing your changes](#testing-your-changes)
- [Community](#community)

---

## Ways to contribute

- **Bug reports** — something doesn't provision correctly or a resource is misconfigured
- **Feature requests** — a missing Azure service, a new HA option, a config knob that should exist
- **Pull requests** — bug fixes, new features, documentation improvements
- **Reviewing PRs** — feedback on open pull requests is always welcome

---

## Reporting issues

Before opening an issue:

1. Search [existing issues](https://github.com/easecloudio/magento2-azure-terraform/issues) to avoid duplicates.
2. Check that you are on the latest commit of `main`.

When opening an issue, include:

- **Terraform version** (`terraform version`)
- **azurerm provider version** (from `.terraform.lock.hcl`)
- **Azure region** where the failure occurs
- The exact **error message** from `terraform plan` or `terraform apply`
- A minimal reproduction — which resource, which config value

**Do not include real credentials, subscription IDs, or IP addresses in issues.**

---

## Development setup

### Requirements

| Tool | Version |
|---|---|
| Terraform | >= 1.9 |
| Azure CLI | latest |
| Git | any recent version |

### Fork and clone

```bash
git clone https://github.com/<your-username>/magento2-azure-terraform.git
cd magento2-azure-terraform
```

### Configure your environment

```bash
cp developer.config.yaml my-dev.config.yaml
# Edit my-dev.config.yaml:
#   brand, codename, domain, admin_email
#   azure.subscription_id, azure.resource_group
#   ssh_public_key
```

### Initialise Terraform

```bash
terraform init
terraform workspace new developer
```

### (Optional) Remote state

Copy `backend.tf.example` to `backend.tf` and fill in a storage account you control. See the README for the one-time setup commands.

---

## Making changes

### Branching

Branch from `main`:

```bash
git checkout -b fix/mysql-delegation-subnet
git checkout -b feat/redis-geo-replication
git checkout -b docs/update-contributing
```

Branch naming conventions:

| Prefix | Use for |
|---|---|
| `fix/` | Bug fixes |
| `feat/` | New features or Azure services |
| `docs/` | Documentation only |
| `refactor/` | Code restructuring with no behaviour change |
| `chore/` | Dependency bumps, CI changes |

### One concern per PR

Keep pull requests focused. A PR that adds Redis geo-replication should not also touch the MySQL configuration. Smaller PRs are reviewed faster and are easier to revert if something goes wrong.

---

## Commit conventions

This project uses [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>: <short description in imperative mood>
```

| Type | When to use |
|---|---|
| `feat` | A new resource, variable, or capability |
| `fix` | A broken configuration or incorrect resource attribute |
| `docs` | README, CONTRIBUTING, comments |
| `refactor` | Restructuring locals, renaming resources — no behaviour change |
| `chore` | Provider version bumps, CI pipeline changes |

**Examples:**

```
feat: add Redis geo-replication with secondary region config
fix: MySQL delegation subnet missing from VNet definition
docs: document waf.admin_allowed_ips config key
refactor: extract appgw locals into locals.tf
chore: bump azurerm provider to 4.1
```

Keep the subject line under 72 characters. No period at the end. No `Co-Authored-By` lines.

---

## Pull request process

1. **Validate locally** before pushing:

   ```bash
   terraform fmt -check -recursive
   terraform validate
   ```

2. **Push your branch** and open a PR against `main`:

   ```bash
   git push origin fix/my-change
   ```

3. **Fill in the PR template** — describe what changed, why, and how to test it.

4. **CI must pass** — the GitHub Actions workflow runs `terraform fmt -check` and `terraform validate` on every PR. Fix any failures before requesting review.

5. **One approval required** from a maintainer before merge.

6. **Squash on merge** — maintainers squash PRs to keep the commit history clean.

### Destructive changes

If your change forces replacement of an existing resource (e.g. changing a subnet CIDR, swapping a MySQL SKU, renaming a Key Vault), call it out explicitly in the PR description with:

- Which resource gets destroyed and recreated
- The blast radius (data loss risk, downtime window)
- A migration path for users who have already deployed

---

## Code style

### Terraform formatting

Always run `terraform fmt` before committing. The CI pipeline rejects unformatted code.

```bash
terraform fmt -recursive
```

### File organisation

Each `.tf` file owns one concern. Do not add resources to an unrelated file:

| File | Owns |
|---|---|
| `vpc_network.tf` | VNet and subnets |
| `security_groups.tf` | NSGs and associations |
| `compute.tf` | VMSS and autoscale |
| `load_balancer.tf` | App Gateway, WAF policy |
| `cdn.tf` | Front Door profile, endpoints, custom domains |
| `dns.tf` | DNS zone and records |
| `database.tf` | MySQL Flexible Server |
| `cache.tf` | Redis |
| `search.tf` | OpenSearch cluster and internal LB |
| `filesystem.tf` | Azure Files NFS |
| `storage.tf` | Blob Storage and Storage Queue |
| `queue.tf` | Service Bus |
| `secrets.tf` | Key Vault and secrets |
| `monitoring.tf` | Azure Monitor alerts |
| `bastion.tf` | Azure Bastion |
| `budget.tf` | Consumption budget |

### Naming

- Resource names follow the pattern `${local.project}-<service>` so every resource is identifiable by environment.
- Locals go in `locals.tf`, not scattered across files.
- New config keys go in `developer.config.yaml` with sensible defaults.

### No hardcoded values

Any value that differs between developer / staging / production must come from `local.env.*` (i.e. the YAML config). Never hardcode region strings, SKUs, or sizes directly in a resource.

**Wrong:**
```hcl
size = "Standard_D2ps_v5"
```

**Right:**
```hcl
size = local.env.opensearch.vm_size
```

### Comments

Only add a comment when the **why** is non-obvious. Do not describe what the code does — well-named resources already do that.

---

## Adding a new environment config key

1. Add the key with a sensible default to `developer.config.yaml`.
2. Reference it in the relevant `.tf` file via `local.env.<key>`.
3. Document the key in the Configuration Reference table in `README.md`.

---

## Adding a new Azure service

1. Create a new `.tf` file named after the concern (e.g. `email.tf` for Azure Communication Services).
2. Add any required subnets or NSG rules to the existing networking files.
3. Add config keys to `developer.config.yaml` and document them in `README.md`.
4. Add relevant Azure Monitor alerts to `monitoring.tf`.
5. Add the new file to the File Structure table in `README.md`.
6. Test with `terraform validate` and a full `terraform plan` against a real Azure subscription.

---

## Testing your changes

There is no Terraform unit test framework in use. Validation happens at two levels:

### Static (always required)

```bash
terraform fmt -check -recursive   # formatting
terraform validate                 # syntax and type checking
```

Both run automatically on every push via GitHub Actions.

### Live (for non-trivial changes)

A full `terraform plan` against a real Azure developer subscription. You do not need to `apply` — the plan output is sufficient to verify resource changes for a PR. Paste the relevant plan diff into the PR description for reviewer context.

When a change is applied:

1. Use the `developer` workspace against a throwaway Azure subscription or resource group.
2. Confirm the expected resources are created and no unexpected ones are destroyed.
3. Run `terraform destroy` to clean up after testing.

---

## Community

- **Issues and PRs** are the primary communication channel.
- Be respectful and constructive — this project follows the [Contributor Covenant](https://www.contributor-covenant.org/) Code of Conduct.
- For questions that aren't bugs or feature requests, open a [GitHub Discussion](https://github.com/easecloudio/magento2-azure-terraform/discussions).
