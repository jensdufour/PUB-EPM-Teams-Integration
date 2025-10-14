# ============================================================================
# EPM Approval Workflow - Validation Script
# ============================================================================
# This script validates the Bicep template before deployment
# ============================================================================

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ResourceGroupName = "rg-epm-approval",
    
    [Parameter(Mandatory = $false)]
    [string]$ParameterFile = "main.bicepparam"
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

function Test-BicepSyntax {
    Write-Status "Validating Bicep syntax..."
    
    try {
        $build = az bicep build --file "main.bicep" 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            Write-Status "Bicep syntax is valid" "Success"
            return $true
        }
        else {
            Write-Status "Bicep syntax validation failed:" "Error"
            Write-Host $build -ForegroundColor Red
            return $false
        }
    }
    catch {
        Write-Status "Error during Bicep validation: $($_.Exception.Message)" "Error"
        return $false
    }
}

function Test-ParameterFile {
    Write-Status "Validating parameter file..."
    
    if (-not (Test-Path $ParameterFile)) {
        Write-Status "Parameter file not found: $ParameterFile" "Error"
        return $false
    }
    
    # Read parameter file content
    $content = Get-Content $ParameterFile -Raw
    
    # Check for placeholder values
    $placeholders = @(
        "YOUR_TEAMS_TEAM_ID",
        "YOUR_TEAMS_CHANNEL_ID",
        "YOUR_SUBSCRIPTION_ID",
        "YOUR_RG",
        "YOUR_WORKSPACE_NAME"
    )
    
    $foundPlaceholders = @()
    foreach ($placeholder in $placeholders) {
        if ($content -match $placeholder) {
            $foundPlaceholders += $placeholder
        }
    }
    
    if ($foundPlaceholders.Count -gt 0) {
        Write-Status "Found placeholder values in parameter file:" "Warning"
        foreach ($placeholder in $foundPlaceholders) {
            Write-Host "   - $placeholder" -ForegroundColor Yellow
        }
        Write-Status "Please update these values before deployment" "Warning"
        return $false
    }
    
    Write-Status "Parameter file is valid" "Success"
    return $true
}

function Test-AzureDeployment {
    Write-Status "Running deployment validation (what-if)..."
    
    try {
        # Check if resource group exists
        $rg = az group show --name $ResourceGroupName --output json 2>$null | ConvertFrom-Json
        
        if (-not $rg) {
            Write-Status "Resource group '$ResourceGroupName' does not exist." "Error"
            Write-Status "Please create the resource group first or run deploy.ps1 which will create it." "Warning"
            return $false
        }
        
        # Run what-if
        Write-Status "Running what-if analysis..."
        $whatif = az deployment group what-if `
            --resource-group $ResourceGroupName `
            --template-file "main.bicep" `
            --parameters $ParameterFile `
            --no-pretty-print 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "`n$whatif`n" -ForegroundColor Cyan
            Write-Status "Deployment validation passed" "Success"
            return $true
        }
        else {
            Write-Status "Deployment validation failed:" "Error"
            Write-Host $whatif -ForegroundColor Red
            return $false
        }
    }
    catch {
        Write-Status "Error during deployment validation: $($_.Exception.Message)" "Error"
        return $false
    }
}

function Test-WorkflowFile {
    Write-Status "Validating workflow.json..."
    
    if (-not (Test-Path "workflow.json")) {
        Write-Status "workflow.json not found" "Error"
        return $false
    }
    
    try {
        $workflow = Get-Content "workflow.json" -Raw | ConvertFrom-Json
        
        # Check required properties
        $requiredProps = @('$schema', 'contentVersion', 'parameters', 'triggers', 'actions')
        $missingProps = @()
        
        foreach ($prop in $requiredProps) {
            if (-not ($workflow.PSObject.Properties.Name -contains $prop)) {
                $missingProps += $prop
            }
        }
        
        if ($missingProps.Count -gt 0) {
            Write-Status "Missing required properties in workflow.json:" "Error"
            foreach ($prop in $missingProps) {
                Write-Host "   - $prop" -ForegroundColor Red
            }
            return $false
        }
        
        Write-Status "workflow.json is valid" "Success"
        return $true
    }
    catch {
        Write-Status "Invalid JSON in workflow.json: $($_.Exception.Message)" "Error"
        return $false
    }
}

function Test-Prerequisites {
    Write-Status "Checking prerequisites..."
    
    $allValid = $true
    
    # Check files exist
    $files = @("main.bicep", "main.bicepparam", "workflow.json")
    foreach ($file in $files) {
        if (Test-Path $file) {
            Write-Status "Found: $file" "Success"
        }
        else {
            Write-Status "Missing: $file" "Error"
            $allValid = $false
        }
    }
    
    # Check Azure CLI
    try {
        $azVersion = az version --output json | ConvertFrom-Json
        Write-Status "Azure CLI version: $($azVersion.'azure-cli')" "Success"
    }
    catch {
        Write-Status "Azure CLI is not installed" "Error"
        $allValid = $false
    }
    
    # Check Bicep
    try {
        $bicepVersion = az bicep version
        Write-Status "Bicep version: $bicepVersion" "Success"
    }
    catch {
        Write-Status "Bicep is not installed" "Error"
        $allValid = $false
    }
    
    # Check if logged in
    try {
        $account = az account show --output json | ConvertFrom-Json
        Write-Status "Logged in as: $($account.user.name)" "Success"
    }
    catch {
        Write-Status "Not logged in to Azure. Run 'az login'" "Error"
        $allValid = $false
    }
    
    return $allValid
}

# ============================================================================
# Main Execution
# ============================================================================

Write-Host "`n============================================================================" -ForegroundColor Cyan
Write-Host "EPM Approval Workflow - Validation Script" -ForegroundColor Cyan
Write-Host "============================================================================`n" -ForegroundColor Cyan

$validationResults = @{
    Prerequisites     = $false
    BicepSyntax       = $false
    WorkflowFile      = $false
    ParameterFile     = $false
    DeploymentWhatIf  = $false
}

# Run all validations
$validationResults.Prerequisites = Test-Prerequisites
Write-Host ""

if ($validationResults.Prerequisites) {
    $validationResults.BicepSyntax = Test-BicepSyntax
    Write-Host ""
    
    $validationResults.WorkflowFile = Test-WorkflowFile
    Write-Host ""
    
    $validationResults.ParameterFile = Test-ParameterFile
    Write-Host ""
    
    if ($validationResults.BicepSyntax -and 
        $validationResults.WorkflowFile -and 
        $validationResults.ParameterFile) {
        
        $validationResults.DeploymentWhatIf = Test-AzureDeployment
        Write-Host ""
    }
}

# Summary
Write-Host "============================================================================" -ForegroundColor Cyan
Write-Host "Validation Summary" -ForegroundColor Cyan
Write-Host "============================================================================`n" -ForegroundColor Cyan

$allPassed = $true
foreach ($key in $validationResults.Keys) {
    $status = if ($validationResults[$key]) { "[PASSED]" } else { "[FAILED]"; $allPassed = $false }
    $color = if ($validationResults[$key]) { "Green" } else { "Red" }
    Write-Host "$($key.PadRight(25)) : $status" -ForegroundColor $color
}

Write-Host "`n============================================================================`n" -ForegroundColor Cyan

if ($allPassed) {
    Write-Status "All validations passed! Ready to deploy." "Success"
    Write-Status "Run .\deploy.ps1 to deploy the solution" "Success"
    exit 0
}
else {
    Write-Status "Some validations failed. Please fix the issues above." "Error"
    exit 1
}
