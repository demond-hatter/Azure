<#
.SYNOPSIS
    Bulk update of License Type or ESU settings
.DESCRIPTION
    This script provides a scaleable solution to set or change the license type and/or enable or disable the ESU policy 
    on all Azure-connected SQL Servers in a specified scope.
    
    You can specfy a single subscription to scan, or provide subscriptions as a .CSV file with the list of IDs.
    If not specified, all subscriptions your role has access to are scanned.
 .PARAMETER SubId 
    [subscription_id] | [csv_file_name]    
    Optional. Limits the scope to specific subscriptions. Accepts a .csv file with the list of subscriptions.
    If not specified all subscriptions will be scanned
 .PARAMETER ResourceGroup 
    Optional. Limits the scope to a specific resoure group
 .PARAMETER MachineName 
    Optional. Limits the scope to a specific machine)
 .PARAMETER LicenseType 
    Optional. Sets the license type to the specified value
 .PARAMETER EnabelESU  
    [Yes or No]                       
    Optional. Enables the ESU policy the value is "Yes" or disables it if the value is "No"
    To enable, the license type must be "Paid" or "PAYG"
 .PARAMETER Force
    Optional. Forces the chnahge of the license type to the specified value on all installed extensions.
    If Force is not specified, the -LicenseType value is set only if undefined. Ignored if -LicenseType  is not specified
.Notes
    This sample script is not supported under any Microsoft standard support program or service. 
    The sample script is provided AS IS without warranty of any kind. Microsoft further disclaims 
    all implied warranties including, without limitation, any implied warranties of merchantability 
    or of fitness for a particular purpose. The entire risk arising out of the use or performance of 
    the sample scripts and documentation remains with you. In no event shall Microsoft, its authors, 
    or anyone else involved in the creation, production, or delivery of the scripts be liable for any 
    damages whatsoever (including, without limitation, damages for loss of business profits, business 
    interruption, loss of business information, or other pecuniary loss) arising out of the use of or 
    inability to use the sample scripts or documentation, even if Microsoft has been advised of the 
    possibility of such damages 

    This script uses a function ConvertTo-HashTable that was created by Adam Bertram (@adam-bertram).
    The function was originally published on https://4sysops.com/archives/convert-json-to-a-powershell-hash-table/
    and is used here with the author's permission.
#>
[CmdletBinding()]
param (
    [Parameter (Mandatory=$false)]
    [string] $SubId,
    [Parameter (Mandatory= $false)]
    [string] $ResourceGroup,
    [Parameter (Mandatory= $false)]
    [string] $MachineName,
    [Parameter (Mandatory= $false)]
    [ValidateSet("PAYG","Paid","LicenseOnly", IgnoreCase=$false)]
    [string] $LicenseType,
    [Parameter (Mandatory= $false)]
    [ValidateSet("Yes","No", IgnoreCase=$false)]
    [string] $EnableESU,
    [Parameter (Mandatory= $false)]
    [switch] $Force
)

function ConvertTo-Hashtable {
    [CmdletBinding()]
    [OutputType('hashtable')]
    param (
        [Parameter(ValueFromPipeline)]
        $InputObject
    )
    process {
        ## Return null if the input is null. This can happen when calling the function
        ## recursively and a property is null
        if ($null -eq $InputObject) {
            return $null
        }
        ## Check if the input is an array or collection. If so, we also need to convert
        ## those types into hash tables as well. This function will convert all child
        ## objects into hash tables (if applicable)
        if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string]) {
            $collection = @(
                foreach ($object in $InputObject) {
                    ConvertTo-Hashtable -InputObject $object
                }
            )
            ## Return the array but don't enumerate it because the object may be pretty complex
            Write-Output -NoEnumerate $collection
        } elseif ($InputObject -is [psobject]) {
            ## If the object has properties that need enumeration, cxonvert it to its own hash table and return it
            $hash = @{}
            foreach ($property in $InputObject.PSObject.Properties) {
                $hash[$property.Name] = ConvertTo-Hashtable -InputObject $property.Value
            }
            $hash
        } else {
            ## If the object isn't an array, collection, or other object, it's already a hash table
            ## So just return it.
            $InputObject
        }
    }
}

# This function checks if the specified module is imported into the session and if not installes and/or imports it
function LoadModule
{
    param (
        [parameter(Mandatory = $true)][string] $name
    )

    $retVal = $true

    if (!(Get-Module -Name $name))
    {
        $retVal = Get-Module -ListAvailable | Where-Object {$_.Name -eq $name}

        if ($retVal)
        {
            try
            {
                Import-Module $name -ErrorAction SilentlyContinue
            }
            catch
            {
                write-host "The request to lload module $($name) failed with the following error:"
                write-host $_.Exception.Message                
                $retVal = $false
            }
        }
        else {

            # If module is not imported, not available on disk, but is in online gallery then install and import
            if (Find-Module -Name $name) {
                Install-Module -Name $name -Force -Verbose -Scope CurrentUser
                try
                {
                Import-Module $name -ErrorAction SilentlyContinue
                }
                catch
                {
                    write-host "The request to lload module $($name) failed with the following error:"
                    write-host $_.Exception.Message                
                    $retVal = $false
                }
            }
            else {

                # If module is not imported, not available and not in online gallery then abort
                write-host "Module $($name) not imported, not available and not in online gallery, exiting."
                EXIT 1
            }
        }
    }

    return $retVal
}

#
# Suppress warnings
#
Update-AzConfig -DisplayBreakingChangeWarning $false

# Load required modules
$requiredModules = @(
    "Az.Accounts",
    "Az.ConnectedMachine",
    "Az.ResourceGraph"
)
write-verbose "Loading required modules"
$requiredModules | Foreach-Object {LoadModule $_ -verbose:$false}

# Subscriptions to scan

##$tenantID = (Get-AzureADTenantDetail).ObjectId
$tenantID = (Get-AzContext).Tenant.Id

if ($SubId -like "*.csv") {
    write-verbose "Importing list of subscriptions from file $SubId"
    $subscriptions = Import-Csv $SubId
}elseif($SubId -ne ""){
    write-verbose "Single subscription provided $SubId"
    $subscriptions = [PSCustomObject]@{SubscriptionId = $SubId} | Get-AzSubscription -TenantID $tenantID
}else{
    write-verbose "No explicit subscription provided. Getting all subscriptions accessible by the specified user"
    $subscriptions = Get-AzSubscription -TenantID $tenantID
}


Write-Host ([Environment]::NewLine + "-- Scanning subscription(s) --")

# Scan arc-enabled servers in each subscription

foreach ($sub in $subscriptions){

    if ($sub.State -ne "Enabled") {continue}

    try {
        Set-AzContext -SubscriptionId $sub.Id -Tenant $tenantID
    }catch {
        write-host "Invalid subscription: $($sub.Id)"
        {continue}
    }

    $query = "
    resources
    | where type =~ 'microsoft.hybridcompute/machines/extensions'
    | where subscriptionId =~ '$($sub.Id)'
    | extend extensionPublisher = tostring(properties.publisher), extensionType = tostring(properties.type), provisioningState = tostring(properties.provisioningState)
    | parse id with * '/providers/Microsoft.HybridCompute/machines/' machineName '/extensions/' *
    | where extensionPublisher =~ 'Microsoft.AzureData'
    | where provisioningState =~ 'Succeeded'
    "
    
    if ($ResourceGroup) {
        $query += "| where resourceGroup =~ '$($ResourceGroup)'"
    }

    if ($MachineName) {
        $query += "| where machineName =~ '$($MachineName)'"
    } 
    
    $query += "
    | project machineName, extensionName = name, resourceGroup, location, subscriptionId, extensionPublisher, extensionType, properties
    "

write-verbose "Executing resource graph query: $query"
    $resources = Search-AzGraph -Query "$($query)"
write-verbose "Number of results returned from query: $($resources.Count)"    
    foreach ($r in $resources) {
        write-verbose "Processing machine: $($r.MachineName)"
        $setID = @{
            MachineName = $r.MachineName
            Name = $r.extensionName
            ResourceGroup = $r.resourceGroup
            Location = $r.location
            SubscriptionId = $r.subscriptionId
            Publisher = $r.extensionPublisher
            ExtensionType = $r.extensionType
        }

        $WriteSettings = $false
        $settings = @{}
        $settings = $r.properties.settings | ConvertTo-Json | ConvertFrom-Json | ConvertTo-Hashtable
        write-verbose "Current machine settings: $($r.properties.settings)"

        # set the license type or update (if -Force). ESU  must be disabled to set to LicenseOnly. 
        $LO_Allowed = (!$settings["enableExtendedSecurityUpdates"] -and !$EnableESU) -or  ($EnableESU -eq "No")
        write-verbose "Is LicenseOnly license type allowed for $($r.machineName): $LO_Allowed"
        if ($LicenseType) {
            if (($LicenseType -eq "LicenseOnly") -and !$LO_Allowed) {
                write-host "ESU must be disabled before license type can be set to $($LicenseType)"
            } else {
                if ($settings.ContainsKey("LicenseType")) {
                    if ($Force) {
                        write-verbose "A forced change in license type has been requested"
                        write-verbose "Current LicenseType: $($settings["LicenseType"])"
                        $settings["LicenseType"] = $LicenseType
                        $WriteSettings = $true
                    }
                } else {
                    write-verbose "A change in license type has been requested"
                    $settings["LicenseType"] = $LicenseType
                    $WriteSettings = $true
                }
            }
            
        }
        
        # Enable ESU for qualified license types or disable 
        if ($EnableESU) {
            if (($settings["LicenseType"] -Contains "Paid" -or "PAYG") -or  ($EnableESU -eq "No")) {
                write-verbose "Extended Security Updates (ESU) has been requested to be enabled"
                $settings["enableExtendedSecurityUpdates"] = ($EnableESU -eq "Yes")
                $settings["esuLastUpdatedTimestamp"] = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
                $WriteSettings = $true
            } else {
                write-host "The configured license type does not support ESUs" 
            }
        }

        If ($WriteSettings) {
            write-verbose "Updating machine settings: $WriteSettings"
            Write-Host "Resource group: [$($r.resourceGroup)] Connected machine: [$($r.MachineName)] : License type: [$($settings["LicenseType"])] : Enable ESU: [$($settings["enableExtendedSecurityUpdates"])]"
            try { 
                Set-AzConnectedMachineExtension @setId -Settings $settings -NoWait | Out-Null
            } catch {
                write-host "The request to modify the extenion object failed with the following error:"
                write-host $_.Exception.Message
                {continue}
            }
        }
    }
}

    