##################################
# EDIT THE FOLLOWING PARAMETERS
#
# tenant_id :                   Active directory's ID
#                               (Portal) Azure AD -> Properties -> Directory ID
#
# subscription_id:              Subscription ID that you want to onboard
#                               Custom role are going to be created from this subscription
#                               Please use a permanent subscription
#
# service_principal_password:   Specify the service principal password.
#                               Use a strong password. Preferrably 30+ character long
#                               IF YOU change the password, you need to update each onboarded subscription on Prisma Cloud
#
variable "tenant_id" {
  type = string
  default = "179d26d3-3e59-4051-9377-05d3820e617c"
}
variable "subscription_id" {
  type = string
  default = "ca65b24d-06d8-468f-b23f-88a61e735aa5"
}
variable "application_password" {
  type = string
  default = "yQ%qso7esINTDJdkDmZf"
}

# By default setting the password to last for a year
variable "application_password_expiration" {
  type = string
  default = "8760h"
}

# The list of permissions added to the custom role
variable "custom_role_permissions" {
    type = list(string)
    default = [
      "Microsoft.Network/networkInterfaces/effectiveNetworkSecurityGroups/action",
      "Microsoft.Network/networkWatchers/securityGroupView/action",
      "Microsoft.Network/networkWatchers/queryFlowLogStatus/action",
      "Microsoft.Network/virtualwans/vpnconfiguration/action",
      "Microsoft.ContainerRegistry/registries/webhooks/getCallbackConfig/action",
      "Microsoft.Web/sites/config/list/action",
      "Microsoft.Storage/storageAccounts/*", # enable remediation for storage account
    ]
}


#############################
# Initializing the provider
##############################

provider "azuread" {
  subscription_id = var.subscription_id
  tenant_id = var.tenant_id
}

provider "azurerm" {
  version = "=2.0.0"
  subscription_id = var.subscription_id
  tenant_id = var.tenant_id
  features {}
}

provider "random" {}


#######################################################
# Setting up an Application & Service Principal
# Will be shared by all of the onboarded subscriptions
#######################################################
resource "random_string" "unique_id" {
  length = 5
  min_lower = 5
  special = false
}

resource "azuread_application" "prisma_cloud_app" {
  name                       = "Prisma Cloud Onboarding ${random_string.unique_id.result}"
  homepage                   = "https://prismacloud.io/"
  available_to_other_tenants = true
}

resource "azuread_service_principal" "prisma_cloud_sp" {
  application_id = azuread_application.prisma_cloud_app.application_id
}


resource "azuread_application_password" "password" {
  value                = var.application_password
  end_date             = timeadd(timestamp(),var.application_password_expiration)
  application_object_id = azuread_application.prisma_cloud_app.object_id
}


#######################################################
# Setting up custom roles
#######################################################
resource "random_uuid" "custom_role_uuid" {}

resource "azurerm_role_definition" "custom_prisma_role" {
  name        = "prisma-cloud-policy-${random_string.unique_id.result}"
  role_definition_id = random_uuid.custom_role_uuid.result
  scope       = "/subscriptions/${var.subscription_id}"
  description = "Prisma Cloud custom role created via Terraform"
  assignable_scopes = ["/subscriptions/${var.subscription_id}"]
  permissions {
    actions     = var.custom_role_permissions
    not_actions = []
  }
}

resource "azurerm_role_assignment" "assign_custom_prisma_role" {
  scope       = "/subscriptions/${var.subscription_id}"
  principal_id = azuread_service_principal.prisma_cloud_sp.id
  role_definition_id = azurerm_role_definition.custom_prisma_role.id
}

resource "azurerm_role_assignment" "assign_reader" {
  scope       = "/subscriptions/${var.subscription_id}"
  principal_id = azuread_service_principal.prisma_cloud_sp.id
  role_definition_name = "Reader"
}


resource "azurerm_role_assignment" "assign_reader_data_access" {
  scope       = "/subscriptions/${var.subscription_id}"
  principal_id = azuread_service_principal.prisma_cloud_sp.id
  role_definition_name = "Reader and Data Access"
}

resource "azurerm_role_assignment" "assign_network_contrib" {
  scope       = "/subscriptions/${var.subscription_id}"
  principal_id = azuread_service_principal.prisma_cloud_sp.id
  role_definition_name = "Network Contributor"
}


output "a__subscription_ids" { value = var.subscription_id }
output "b__tenant_ids" { value = var.tenant_id}
output "c__application_id" { value = azuread_application.prisma_cloud_app.application_id}
output "d__application_key" { value = var.application_password}
output "e__service_principal_object_id" { value = azuread_service_principal.prisma_cloud_sp.id}
