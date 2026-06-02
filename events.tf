
///////////////////////////////////////////////////////////[ AZURE EVENT GRID ]/////////////////////////////////////////////////////

resource "azurerm_eventgrid_system_topic" "storage" {
  name                   = "${local.project}-storage-events"
  resource_group_name    = azurerm_resource_group.this.name
  location               = azurerm_resource_group.this.location
  source_arm_resource_id = azurerm_storage_account.this.id
  topic_type             = "Microsoft.Storage.StorageAccounts"
  tags                   = local.default_tags
}

# Note: the webhook URL below is a placeholder. In practice this should point
# to an Azure Function or Logic App that handles release deployment automation.
resource "azurerm_eventgrid_system_topic_event_subscription" "release_deploy" {
  name                = "${local.project}-release-deploy"
  system_topic        = azurerm_eventgrid_system_topic.storage.name
  resource_group_name = azurerm_resource_group.this.name

  included_event_types = ["Microsoft.Storage.BlobCreated"]

  subject_filter {
    subject_begins_with = "/blobServices/default/containers/system/blobs/release/"
  }

  webhook_endpoint {
    url = "https://placeholder.example.com/webhook"
  }
}
