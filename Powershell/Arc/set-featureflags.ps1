


# List of required extensions
$requiredExtensions = @("arcdata", "connectedmachine", "resource-graph")

foreach ($ext in $requiredExtensions) {
    $check = az extension list --query "[?name=='$ext']" --output json | ConvertFrom-Json
    if ($check.Count -gt 0) {
        Write-Host "Extension '$ext' is already installed. ✅" -ForegroundColor Green
    } else {
        Write-Host "Extension '$ext' is not installed. Installing..." -ForegroundColor Yellow
        az extension add --name $ext
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Extension '$ext' installed successfully. 🎉" -ForegroundColor Cyan
        } else {
            Write-Host "Failed to install extension '$ext'. ❌" -ForegroundColor Red
        }
    }
}


# Set your resource group name

RESOURCE_GROUP=""
SUBSCRIPTION =""
# Get all Arc-connected machines in the resource group
machines=$(az resource list \
  --resource-group $RESOURCE_GROUP \
  --resource-type "Microsoft.HybridCompute/machines" \
  --query "[].name" -o tsv)

# Loop through each machine and enable LeastPrivilege feature flag
for machine in $machines; do
  echo "Enabling LeastPrivilege for machine: $machine"

  az sql server-arc extension feature-flag set \
    --name LeastPrivilege \
    --enable true \
    --resource-group $RESOURCE_GROUP \
    --machine-name $machine
