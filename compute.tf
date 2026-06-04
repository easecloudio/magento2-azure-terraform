

///////////////////////////////////////////////////////////[ VM SCALE SETS ]/////////////////////////////////////////////////////

resource "azurerm_linux_virtual_machine_scale_set" "this" {
  for_each            = local.env.vmss
  name                = "${local.project}-${each.key}-vmss"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  sku                 = each.value.vm_size
  instances           = each.value.desired_capacity
  admin_username      = local.env.brand
  upgrade_mode        = each.key == "cron" ? "Automatic" : "Rolling"
  zones               = ["1", "2", "3"]

  admin_ssh_key {
    username   = local.env.brand
    public_key = local.env.ssh_public_key
  }

  source_image_reference {
    publisher = "Debian"
    offer     = "debian-12"
    sku       = "12-gen2"
    version   = "latest"
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = each.value.os_disk_size_gb
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.compute.id]
  }

  network_interface {
    name    = "${local.project}-${each.key}-nic"
    primary = true

    ip_configuration {
      name      = "primary"
      primary   = true
      subnet_id = azurerm_subnet.compute.id
      application_gateway_backend_address_pool_ids = each.key == "varnish" ? [
        one([for pool in azurerm_application_gateway.this.backend_address_pool
        : pool.id if pool.name == local.appgw_backend_pool_name])
        ] : each.key == "admin" ? [
        one([for pool in azurerm_application_gateway.this.backend_address_pool
        : pool.id if pool.name == local.appgw_admin_backend_pool_name])
      ] : null
    }
  }

  custom_data = base64encode(templatefile("${path.module}/cloud-init/${each.key}.sh", {
    project     = local.project
    environment = local.environment
    brand       = local.env.brand
    location    = local.env.azure.location
  }))

  dynamic "rolling_upgrade_policy" {
    for_each = each.key != "cron" ? [1] : []
    content {
      max_batch_instance_percent              = 20
      max_unhealthy_instance_percent          = 20
      max_unhealthy_upgraded_instance_percent = 20
      pause_time_between_batches              = "PT0S"
    }
  }

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

  tags = merge(local.default_tags, { instance_type = each.key })

  lifecycle {
    ignore_changes = [instances]
  }
}

resource "azurerm_monitor_autoscale_setting" "this" {
  for_each            = local.env.vmss
  name                = "${local.project}-${each.key}-autoscale"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  target_resource_id  = azurerm_linux_virtual_machine_scale_set.this[each.key].id

  profile {
    name = "default"

    capacity {
      default = each.value.desired_capacity
      minimum = each.value.min_count
      maximum = each.value.max_count
    }

    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = azurerm_linux_virtual_machine_scale_set.this[each.key].id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = local.env.autoscale.out_threshold_percent
      }

      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT${local.env.autoscale.cooldown_minutes}M"
      }
    }

    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = azurerm_linux_virtual_machine_scale_set.this[each.key].id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = local.env.autoscale.in_threshold_percent
      }

      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT${local.env.autoscale.cooldown_minutes}M"
      }
    }
  }

  tags = local.default_tags
}
