using './main.bicep'

// ============================================================================
// Required Parameters - UPDATE THESE VALUES BEFORE DEPLOYMENT
// ============================================================================
// ⚠️ IMPORTANT: Replace the example IDs below with your actual Teams IDs

// Microsoft Teams Team ID where approval messages will be posted
// To get this: Open Teams > Click "..." next to team name > Get link to team
// Extract the groupId from the URL
param teamsTeamId = ''  // ⚠️ REPLACE ME

// Microsoft Teams Channel ID where approval messages will be posted
// To get this: Open Teams > Right-click channel > Get link to channel
// Extract the channel ID from the URL (after /channel/)
param teamsChannelId = ''  // ⚠️ REPLACE ME

// Azure AD Tenant ID for OAuth authentication
// Leave empty to use the current deployment tenant
// To get your Tenant ID: Azure Portal > Azure Active Directory > Overview
param tenantId = '' // ⚠️ REPLACE ME

// ============================================================================
// Optional Parameters - Customize as needed
// ============================================================================

// Azure region for deployment
param location = 'westeurope'

// Name of the Logic App
param logicAppName = 'logic-epm-approval'

// How often to check for new elevation requests (in minutes)
param recurrenceIntervalMinutes = 5

// Microsoft Graph API base URL (use beta for EPM features)
param graphApiBaseUrl = 'https://graph.microsoft.com/beta'

// ============================================================================
// Azure AD OAuth Parameters
// ============================================================================

// Microsoft Graph API audience/resource for OAuth authentication
// Default: https://graph.microsoft.com (do not change unless required)
param graphApiAudience = 'https://graph.microsoft.com'

// ============================================================================
// Monitoring & Diagnostics
// ============================================================================

// Enable diagnostic logging to Log Analytics
param enableDiagnostics = false

// Log Analytics Workspace ID (required if enableDiagnostics is true)
// Example: '/subscriptions/xxxx/resourceGroups/xxxx/providers/Microsoft.OperationalInsights/workspaces/xxxx'
param logAnalyticsWorkspaceId = ''

// Resource tags
param tags = {
  Environment: 'Production'
  Application: 'EPM-Approval-Workflow'
  ManagedBy: 'Bicep'
  CostCenter: 'IT-Security'
}
