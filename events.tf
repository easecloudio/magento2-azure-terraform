
///////////////////////////////////////////////////////////[ AZURE EVENT GRID ]/////////////////////////////////////////////////////

resource "azurerm_eventgrid_system_topic" "storage" {
  name                   = "${local.project}-storage-events"
  resource_group_name    = azurerm_resource_group.this.name
  location               = azurerm_resource_group.this.location
  source_arm_resource_id = azurerm_storage_account.this.id
  topic_type             = "Microsoft.Storage.StorageAccounts"
  tags                   = local.default_tags
}

resource "azurerm_eventgrid_system_topic_event_subscription" "release_deploy" {
  name                = "${local.project}-release-deploy"
  system_topic        = azurerm_eventgrid_system_topic.storage.name
  resource_group_name = azurerm_resource_group.this.name

  included_event_types = ["Microsoft.Storage.BlobCreated"]

  subject_filter {
    subject_begins_with = "/blobServices/default/containers/system/blobs/release/"
  }

  storage_queue_endpoint {
    storage_account_id = azurerm_storage_account.this.id
    queue_name         = azurerm_storage_queue.release_events.name
  }
}
