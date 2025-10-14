# ============================================================================
# EPM Approval Workflow - Deployment Script
# ============================================================================
# This script deploys the Logic App for EPM approval workflow automation
# ============================================================================

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ResourceGroupName = "rg-epm-approval",
    
    [Parameter(Mandatory = $false)]
    [string]$Location = "westeurope",
    
    [Parameter(Mandatory = $false)]
    [string]$ParameterFile = "main.bicepparam",
    
    [Parameter(Mandatory = $false)]
    [switch]$SkipGraphPermissions,
    
    [Parameter(Mandatory = $false)]
    [switch]$WhatIf
)

# ============================================================================
# Functions
# ============================================================================

function Write-Status {
    param([string]$Message, [string]$Type = "Info")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    switch ($Type) {
        "Success" { Write-Host "[$timestamp] [OK] $Message" -ForegroundColor Green }
        "Error"   { Write-Host "[$timestamp] [ERROR] $Message" -ForegroundColor Red }
        "Warning" { Write-Host "[$timestamp] [WARN] $Message" -ForegroundColor Yellow }
        default   { Write-Host "[$timestamp] [INFO] $Message" -ForegroundColor Cyan }
    }
}

function Test-Prerequisites {
    Write-Status "Checking prerequisites..."
    
    # Check Azure CLI
    try {
        $azVersion = az version --output json | ConvertFrom-Json
        Write-Status "Azure CLI version: $($azVersion.'azure-cli')" "Success"
    }
    catch {
        Write-Status "Azure CLI is not installed. Please install from: https://aka.ms/InstallAzureCLI" "Error"
        return $false
    }
    
    # Check Bicep
    try {
        $bicepVersion = az bicep version
        Write-Status "Bicep version: $bicepVersion" "Success"
    }
    catch {
        Write-Status "Installing Bicep..." "Warning"
        az bicep install
    }
    
    # Check if logged in
    try {
        $account = az account show --output json | ConvertFrom-Json
        Write-Status "Logged in as: $($account.user.name)" "Success"
        Write-Status "Subscription: $($account.name) ($($account.id))" "Success"
    }
    catch {
        Write-Status "Not logged in to Azure. Please run 'az login'" "Error"
        return $false
    }
    
    # Check parameter file
    if (-not (Test-Path $ParameterFile)) {
        Write-Status "Parameter file not found: $ParameterFile" "Error"
        return $false
    }
    Write-Status "Parameter file found: $ParameterFile" "Success"
    
    return $true
}

function New-ResourceGroupIfNotExists {
    Write-Status "Checking resource group: $ResourceGroupName..."
    
    $rg = az group show --name $ResourceGroupName --output json 2>$null | ConvertFrom-Json
    
    if (-not $rg) {
        Write-Status "Creating resource group: $ResourceGroupName in $Location..."
        if ($WhatIf) {
            Write-Status "[WHATIF] Would create resource group: $ResourceGroupName" "Warning"
        }
        else {
            az group create --name $ResourceGroupName --location $Location --output none
            if ($LASTEXITCODE -eq 0) {
                Write-Status "Resource group created successfully" "Success"
            }
            else {
                Write-Status "Failed to create resource group" "Error"
                return $false
            }
        }
    }
    else {
        Write-Status "Resource group already exists" "Success"
    }
    
    return $true
}

function Deploy-BicepTemplate {
    Write-Status "Starting deployment..."
    
    if ($WhatIf) {
        Write-Status "[WHATIF] Would deploy template with parameters from: $ParameterFile" "Warning"
        az deployment group what-if `
            --resource-group $ResourceGroupName `
            --template-file "main.bicep" `
            --parameters $ParameterFile
    }
    else {
        $deploymentName = "epm-approval-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        
        Write-Status "Deployment name: $deploymentName"
        
        $deployment = az deployment group create `
            --resource-group $ResourceGroupName `
            --name $deploymentName `
            --template-file "main.bicep" `
            --parameters $ParameterFile `
            --output json | ConvertFrom-Json
        
        if ($LASTEXITCODE -eq 0) {
            Write-Status "Deployment completed successfully" "Success"
            return $deployment
        }
        else {
            Write-Status "Deployment failed" "Error"
            return $null
        }
    }
}

function Set-GraphApiPermissions {
    param([string]$PrincipalId)
    
    if ($SkipGraphPermissions) {
        Write-Status "Skipping Graph API permissions assignment (use -SkipGraphPermissions to skip)" "Warning"
        return $true
    }
    
    Write-Status "Assigning Graph API permissions to Managed Identity..."
    
    try {
        # Check if Microsoft.Graph module is installed
        if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Authentication)) {
            Write-Status "Microsoft.Graph module not found. Installing..." "Warning"
            Install-Module Microsoft.Graph.Authentication -Scope CurrentUser -Force -AllowClobber
            Install-Module Microsoft.Graph.Applications -Scope CurrentUser -Force -AllowClobber
        }
        
        # Import required modules
        Import-Module Microsoft.Graph.Authentication -Force
        Import-Module Microsoft.Graph.Applications -Force
        
        # Connect to Microsoft Graph
        Write-Status "Connecting to Microsoft Graph..."
        Connect-MgGraph -Scopes "Application.ReadWrite.All", "AppRoleAssignment.ReadWrite.All" -NoWelcome -ErrorAction Stop
        
        # Get Microsoft Graph Service Principal
        Write-Status "Getting Microsoft Graph service principal..."
        $graphSP = Get-MgServicePrincipal -Filter "appId eq '00000003-0000-0000-c000-000000000000'" -ErrorAction Stop
        
        if (-not $graphSP) {
            Write-Status "Microsoft Graph service principal not found" "Error"
            return $false
        }
        
        # Define required permissions
        $requiredPermissions = @(
            "DeviceManagementConfiguration.ReadWrite.All",
            "DeviceManagementManagedDevices.Read.All"
        )
        
        foreach ($permissionName in $requiredPermissions) {
            Write-Status "Processing permission: $permissionName..."
            
            # Get the permission
            $permission = $graphSP.AppRoles | Where-Object { $_.Value -eq $permissionName }
            
            if (-not $permission) {
                Write-Status "Permission '$permissionName' not found" "Warning"
                continue
            }
            
            # Check if permission is already assigned
            $existingAssignment = Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $PrincipalId -ErrorAction SilentlyContinue |
                Where-Object { $_.AppRoleId -eq $permission.Id }
            
            if ($existingAssignment) {
                Write-Status "Permission '$permissionName' already assigned" "Success"
            }
            else {
                # Assign the permission
                Write-Status "Assigning permission: $permissionName..."
                New-MgServicePrincipalAppRoleAssignment `
                    -ServicePrincipalId $PrincipalId `
                    -PrincipalId $PrincipalId `
                    -ResourceId $graphSP.Id `
                    -AppRoleId $permission.Id -ErrorAction Stop | Out-Null
                
                Write-Status "Permission '$permissionName' assigned successfully" "Success"
            }
        }
        
        Disconnect-MgGraph | Out-Null
        return $true
    }
    catch {
        Write-Status "Failed to assign Graph API permissions: $($_.Exception.Message)" "Error"
        Write-Status "You can manually assign permissions later using the README instructions" "Warning"
        return $false
    }
}

function Set-TeamsConnectionAuth {
    param(
        [string]$ResourceGroupName,
        [string]$ConnectionName = "teams-connection"
    )
    
    Write-Status "Authorizing Teams API connection..."
    
    try {
        # Get the Teams connection
        $connection = az resource show `
            --resource-group $ResourceGroupName `
            --resource-type "Microsoft.Web/connections" `
            --name $ConnectionName `
            --output json | ConvertFrom-Json
        
        if (-not $connection) {
            Write-Status "Teams connection not found" "Error"
            return $false
        }
        
        # Get the connection runtime URL for consent
        Write-Status "Getting connection consent link..."
        $consentLink = az rest `
            --method POST `
            --uri "$($connection.id)/listConsentLinks?api-version=2016-06-01" `
            --output json | ConvertFrom-Json
        
        if ($consentLink -and $consentLink.value -and $consentLink.value[0].link) {
    Write-Host "`n============================================================================" -ForegroundColor Yellow
    Write-Host "TEAMS CONNECTION AUTHORIZATION REQUIRED" -ForegroundColor Yellow
    Write-Host "============================================================================" -ForegroundColor Yellow
    Write-Status "Please authorize the Teams connection by opening this link:" "Warning"
    Write-Host "`n$($consentLink.value[0].link)`n" -ForegroundColor Cyan
    
    # Try to open the link automatically
    try {
        Start-Process $consentLink.value[0].link
        Write-Status "Opened consent link in browser" "Success"
    }
    catch {
        Write-Status "Could not open browser automatically. Please copy the link above." "Warning"
    }
    
    Write-Host "Press any key after completing the authorization..." -ForegroundColor Yellow
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    Write-Host ""
            
            return $true
        }
        else {
            Write-Status "Connection may already be authorized or consent link not available" "Warning"
            Write-Status "If the Logic App fails, manually authorize the connection in Azure Portal" "Warning"
            return $true
        }
    }
    catch {
        Write-Status "Failed to setup Teams connection authorization: $($_.Exception.Message)" "Warning"
        Write-Status "You can manually authorize the connection in Azure Portal" "Warning"
        return $false
    }
}

# ============================================================================
# Main Execution
# ============================================================================

Write-Host "`n============================================================================" -ForegroundColor Cyan
Write-Host "EPM Approval Workflow - Deployment Script" -ForegroundColor Cyan
Write-Host "============================================================================`n" -ForegroundColor Cyan

# Step 1: Check prerequisites
if (-not (Test-Prerequisites)) {
    Write-Status "Prerequisites check failed. Exiting..." "Error"
    exit 1
}

# Step 2: Create resource group
if (-not (New-ResourceGroupIfNotExists)) {
    Write-Status "Resource group creation failed. Exiting..." "Error"
    exit 1
}

# Step 3: Deploy Bicep template
$deployment = Deploy-BicepTemplate

if (-not $WhatIf -and $deployment) {
    # Step 4: Display outputs
    Write-Host "`n============================================================================" -ForegroundColor Cyan
    Write-Host "Deployment Outputs" -ForegroundColor Cyan
    Write-Host "============================================================================`n" -ForegroundColor Cyan
    
    $outputs = $deployment.properties.outputs
    
    Write-Status "Logic App Name: $($outputs.logicAppName.value)"
    Write-Status "Logic App ID: $($outputs.logicAppId.value)"
    Write-Status "Managed Identity Principal ID: $($outputs.managedIdentityPrincipalId.value)"
    Write-Status "Managed Identity Client ID: $($outputs.managedIdentityClientId.value)"
    
    # Step 5: Assign Graph API permissions
    Write-Host "`n"
    $graphPermsSuccess = Set-GraphApiPermissions -PrincipalId $outputs.managedIdentityPrincipalId.value
    
    # Step 6: Authorize Teams connection
    Write-Host "`n"
    $teamsAuthSuccess = Set-TeamsConnectionAuth -ResourceGroupName $ResourceGroupName
    
    # Step 7: Next steps
    Write-Host "`n============================================================================" -ForegroundColor Cyan
    Write-Host "Deployment Summary" -ForegroundColor Cyan
    Write-Host "============================================================================`n" -ForegroundColor Cyan
    
    Write-Status "[+] Logic App deployed: $($outputs.logicAppName.value)" "Success"
    Write-Status "[+] Managed Identity created: $($outputs.managedIdentityClientId.value)" "Success"
    
    if ($graphPermsSuccess) {
        Write-Status "[+] Graph API permissions assigned" "Success"
    }
    else {
        Write-Status "[!] Graph API permissions need manual setup" "Warning"
    }
    
    if ($teamsAuthSuccess) {
        Write-Status "[+] Teams connection authorized (or already authorized)" "Success"
    }
    else {
        Write-Status "[!] Teams connection needs manual authorization" "Warning"
    }
    
    Write-Host "`n============================================================================" -ForegroundColor Cyan
    Write-Host "Testing the Workflow" -ForegroundColor Cyan
    Write-Host "============================================================================`n" -ForegroundColor Cyan
    
    Write-Status "1. Create an EPM elevation request in Intune:"
    Write-Status "   - Go to Intune > Endpoint security > Endpoint Privilege Management"
    Write-Status "   - Create a test elevation request from a managed device"
    Write-Status ""
    Write-Status "2. The Logic App will automatically:"
    Write-Status "   - Check for pending requests every 5 minutes"
    Write-Status "   - Post approval cards to your Teams channel"
    Write-Status "   - Wait for approval/denial actions"
    Write-Status ""
    Write-Status "3. Monitor the workflow:"
    Write-Status "   - Azure Portal > Logic Apps > $($outputs.logicAppName.value) > Runs history"
    Write-Status "   - View run details, inputs, and outputs for troubleshooting"
    Write-Status ""
    
    if (-not $graphPermsSuccess -or -not $teamsAuthSuccess) {
        Write-Host "`n============================================================================" -ForegroundColor Yellow
        Write-Host "Manual Steps Required" -ForegroundColor Yellow
        Write-Host "============================================================================`n" -ForegroundColor Yellow
        
        if (-not $graphPermsSuccess) {
            Write-Status "Graph API Permissions:" "Warning"
            Write-Status "1. Go to Azure Portal > Azure Active Directory > Enterprise Applications"
            Write-Status "2. Search for the Managed Identity: $($outputs.managedIdentityPrincipalId.value)"
            Write-Status "3. Go to Permissions > Add permission > Microsoft Graph > Application permissions"
            Write-Status "4. Add: DeviceManagementConfiguration.ReadWrite.All"
            Write-Status "5. Add: DeviceManagementManagedDevices.Read.All"
            Write-Status "6. Click 'Grant admin consent'"
            Write-Status ""
        }
        
        if (-not $teamsAuthSuccess) {
            Write-Status "Teams Connection Authorization:" "Warning"
            Write-Status "1. Go to Azure Portal > Resource Groups > $ResourceGroupName"
            Write-Status "2. Find API Connection: 'teams-connection'"
            Write-Status "3. Click 'Edit API connection' > 'Authorize' > Sign in with your account"
            Write-Status "4. Save the connection"
            Write-Status ""
        }
    }
    
    Write-Status "`nDeployment completed successfully!" "Success"
}
elseif ($WhatIf) {
    Write-Status "`nWhatIf operation completed. No changes were made." "Warning"
}
else {
    Write-Status "`nDeployment failed. Check the errors above." "Error"
    exit 1
}
