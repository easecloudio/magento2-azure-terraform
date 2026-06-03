
///////////////////////////////////////////////////////////[ AZURE BUDGET ]/////////////////////////////////////////////////////

data "azurerm_subscription" "current" {}

resource "azurerm_consumption_budget_subscription" "this" {
  name            = "${local.project}-budget"
  subscription_id = data.azurerm_subscription.current.id

  amount     = local.env.budget.amount
  time_grain = "Monthly"

  time_period {
    start_date = local.env.budget.start_date
  }

  notification {
    enabled        = true
    threshold      = 75
    operator       = "GreaterThan"
    threshold_type = "Forecasted"

    contact_emails = [local.env.admin_email]
  }

  notification {
    enabled        = true
    threshold      = local.env.budget.threshold_percent
    operator       = "GreaterThan"
    threshold_type = "Actual"

    contact_emails = [local.env.admin_email]
  }
}
