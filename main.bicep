// ============================================================================
// EPM Approval Workflow - Logic App with Teams Integration
// ============================================================================
// Purpose: Automate Endpoint Privilege Management approval workflow using
//          Microsoft Teams Adaptive Cards and Microsoft Graph API
// ============================================================================

targetScope = 'resourceGroup'

// ============================================================================
// Parameters
// ============================================================================

@description('Location for all resources')
param location string = resourceGroup().location

@description('Name of the Logic App')
param logicAppName string = 'logic-epm-approval'

@description('Tags to apply to all resources')
param tags object = {
  Environment: 'Production'
  Application: 'EPM-Approval'
  ManagedBy: 'Bicep'
}

@description('Recurrence interval in minutes for checking elevation requests')
@minValue(1)
@maxValue(60)
param recurrenceIntervalMinutes int = 5

@description('Microsoft Teams Team ID where approval messages will be posted')
param teamsTeamId string

@description('Microsoft Teams Channel ID where approval messages will be posted')
param teamsChannelId string

@description('Microsoft Graph API base URL')
param graphApiBaseUrl string = 'https://graph.microsoft.com/beta'

@description('Azure AD Tenant ID for OAuth authentication (leave empty to use current tenant)')
param tenantId string = tenant().tenantId

@description('Microsoft Graph API audience/resource for OAuth authentication')
param graphApiAudience string = 'https://graph.microsoft.com'

@description('Enable diagnostic settings for the Logic App')
param enableDiagnostics bool = true

@description('Log Analytics Workspace ID for diagnostics (required if enableDiagnostics is true)')
param logAnalyticsWorkspaceId string = ''

// ============================================================================
// Variables
// ============================================================================

var managedIdentityName = '${logicAppName}-identity'
var teamsConnectionName = 'teams-connection'

// ============================================================================
// Resources
// ============================================================================

// Managed Identity for Logic App
resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: managedIdentityName
  location: location
  tags: tags
}

// Teams API Connection (uses delegated permissions - user must sign in)
resource teamsConnection 'Microsoft.Web/connections@2016-06-01' = {
  name: teamsConnectionName
  location: location
  tags: tags
  properties: {
    displayName: 'Teams Connection for EPM Approval'
    api: {
      id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'teams')
    }
    parameterValues: {}
  }
}

// Logic App (Consumption)
resource logicApp 'Microsoft.Logic/workflows@2019-05-01' = {
  name: logicAppName
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}': {}
    }
  }
  properties: {
    state: 'Enabled'
    definition: loadJsonContent('workflow.json').definition
    parameters: {
      '$connections': {
        value: {
          teams: {
            connectionId: teamsConnection.id
            connectionName: teamsConnection.name
            id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'teams')
          }
        }
      }
      graphApiBaseUrl: {
        value: graphApiBaseUrl
      }
      teamsTeamId: {
        value: teamsTeamId
      }
      teamsChannelId: {
        value: teamsChannelId
      }
      recurrenceIntervalMinutes: {
        value: recurrenceIntervalMinutes
      }
      tenantId: {
        value: tenantId
      }
      graphApiAudience: {
        value: graphApiAudience
      }
      managedIdentityClientId: {
        value: managedIdentity.properties.clientId
      }
      managedIdentityResourceId: {
        value: managedIdentity.id
      }
    }
  }
}

// Diagnostic Settings for Logic App
resource diagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableDiagnostics && !empty(logAnalyticsWorkspaceId)) {
  scope: logicApp
  name: '${logicAppName}-diagnostics'
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        category: 'WorkflowRuntime'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
    ]
  }
}

// ============================================================================
// Outputs
// ============================================================================

@description('The resource ID of the Logic App')
output logicAppId string = logicApp.id

@description('The name of the Logic App')
output logicAppName string = logicApp.name

@description('The resource ID of the the Managed Identity (use this to assign Graph API permissions)')
output managedIdentityId string = managedIdentity.id

@description('The Principal ID of the Managed Identity (use this to assign Graph API permissions)')
output managedIdentityPrincipalId string = managedIdentity.properties.principalId

@description('The Client ID of the Managed Identity')
output managedIdentityClientId string = managedIdentity.properties.clientId
