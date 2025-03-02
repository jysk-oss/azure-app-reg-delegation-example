terraform {
  required_providers {
    azuread = {
      source  = "hashicorp/azuread"
      version = "3.1.0"
    }
  }
}

# Tenant ID. Change to fit your needs.
provider "azuread" {
  tenant_id = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
}

# The url for the oauth2proxy/termpad.
locals {
  termpad_url = "https://termpad.your-domain.net"
}

############################################################
#                   Microsoft Graph API                    #
############################################################

# Retrieves the UUID for Microsoft Graph API and other well-known delegated permissions.
# These identifiers will be used by Azure AD applications to request access.

data "azuread_application_published_app_ids" "well_known" {}

# References the Microsoft Graph API service principal using its well-known client ID.
# If the service principal already exists, it will be reused instead of creating a new one.
resource "azuread_service_principal" "msgraph" {
  client_id    = data.azuread_application_published_app_ids.well_known.result.MicrosoftGraph
  use_existing = true
}

############################################################
#          Termpad/OAuth2Proxy App Registration            #
############################################################

# Creates an Azure AD application of type "Web", enabling the client-credentials flow
# with a client ID and secret for authentication.
#
# This App Registration is designed for OAuth2Proxy to manage user logins.
# It defines an OAuth 2.0 permission scope (`api://termpad2/access`),
# which is added as a delegated permission for the CLI application.
# Additionally, the application includes the email claim in the access token
# which is used by OAuth2Proxy.

resource "azuread_application" "termpad" {
  display_name    = "termpad"
  identifier_uris = ["api://termpad"]

  # Defines an OAuth 2.0 permission scope to grant access to Termpad.
  api {
    oauth2_permission_scope {
      admin_consent_display_name = "Access"
      value                      = "access"
      admin_consent_description  = "Gives access to termpad"
      id                         = "36118c83-e227-4de4-beae-616ad0b0a895" # Manually generated UUID. https://www.uuidgenerator.net/
      type                       = "User"
    }
  }

  # Grants the application permissions to Microsoft Graph API,
  # specifically requesting the `email` and `User.Read` scopes.
  required_resource_access {
    resource_app_id = data.azuread_application_published_app_ids.well_known.result.MicrosoftGraph

    resource_access {
      id   = azuread_service_principal.msgraph.oauth2_permission_scope_ids["email"]
      type = "Scope"
    }

    resource_access {
      id   = azuread_service_principal.msgraph.oauth2_permission_scope_ids["User.Read"]
      type = "Scope"
    }
  }

  # Configures optional claims to include the user's email in the access token.
  optional_claims {
    access_token {
      name = "email"
    }
  }

  # Configures the web application with redirect and logout URLs.
  web {
    logout_url    = "${local.termpad_url}/oauth2/sign_out"
    redirect_uris = ["${local.termpad_url}/oauth2/callback"]
  }
}

# Grants admin consent for the "email" and "User.Read" delegated permissions
# that were assigned to the Termpad App Registration.

# Registers the Termpad application as a service principal in Azure AD.
resource "azuread_service_principal" "termpad" {
  client_id = azuread_application.termpad.client_id
}

# Grants the Termpad service principal delegated permissions to Microsoft Graph,
# allowing it to access user email and basic profile information.
resource "azuread_service_principal_delegated_permission_grant" "grants" {
  service_principal_object_id          = azuread_service_principal.termpad.object_id
  resource_service_principal_object_id = azuread_service_principal.msgraph.object_id
  claim_values                         = ["email", "User.Read"]
}



############################################################
#                    CLI App Registration                  #
############################################################

# Defines an Azure AD application for a CLI tool, configured as a "Single Page Application" (SPA).
# This enables the authorization flow with PKCE (Proof Key for Code Exchange),
# which is required for secure authentication via the CLI.
#
# The application is granted API permissions for the delegated scope
# "api://termpad/access" to allow it to access the Termpad API.

resource "azuread_application" "cli_client" {
  display_name = "cli-tool"

  # The `redirect_uris` defines a list of allowed URLs where Azure AD can redirect after a successful login.
  # When the CLI initiates authentication, it starts a local web server on `localhost`
  # to receive the authorization code from Azure AD.
  single_page_application {
    redirect_uris = ["http://localhost/"]
  }

  # Assigns the delegated API permission using the scope ID from the Termpad application.
  required_resource_access {
    resource_app_id = azuread_application.termpad.client_id

    resource_access {
      # The UUID from azuread_application.termpad.api.oauth2_permission_scope.id
      id   = "36118c83-e227-4de4-beae-616ad0b0a895"
      type = "Scope"
    }
  }
}

############################################################
#                        Outputs                           #
############################################################

data "azuread_client_config" "current" {}

output "tenant_id" {
  value = data.azuread_client_config.current.tenant_id
}

output "cli_client_id" {
  value = azuread_application.cli_client.client_id
}

output "oauth2_proxy_client_id" {
  value = azuread_application.termpad.client_id
}

output "oauth2_proxy_oidc_issuer_url" {
  value = "https://login.microsoftonline.com/${data.azuread_client_config.current.tenant_id}/v2.0"
}

output "oauth2_proxy_extra_jwt_issuers" {
  value = "https://sts.windows.net/${data.azuread_client_config.current.tenant_id}/=${tolist(azuread_application.termpad.identifier_uris)[0]}"
}


