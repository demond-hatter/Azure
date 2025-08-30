function test-arcConnectivity {
[CmdletBinding()]
    param (
        [Parameter (Mandatory=$true)]
        [ValidateSet("centralus","eastus","eastus2","northcentralus", "southcentralus","westcentralus","westus","westus2","westus3")]
        [string] $region
    )

    $arcEndpoints = @{
        akams = "aka.ms";
        downloads = "download.microsoft.com";
        packages = "packages.microsoft.com";
        entraID_01 = "login.windows.net";
        entraID_02 = "login.microsoftonline.com";
        entraID_03 = "pas.windows.net";
        management = "management.azure.com";
        guestnotificationservice = "guestnotificationservice.azure.com";
        Agent_Telemetry = "dc.services.visualstudio.com";
        ESU_Certificates = "www.microsoft.com";
        DPS = "dataprocessingservice.$region.arcdataservices.com";
        DPS_Telemetry = "telemetry.$region.arcdataservices.com"
    }

    $WldCardArcEndpoints = @{
        hybrid_identity_services = "*.his.arc.azure.com";
        Extension_Management = "*.guestconfiguration.azure.com";
        Notification_Services = "*.guestnotificationservice.azure.com";
        Notification_Services_2 = "azgn*.servicebus.windows.net";
        WindowsAdmin_SSH = "*.servicebus.windows.net";
        Extension_Downloads = "*.blob.core.windows.net"
    }

    Write-host "The following are the TLS protocols available from this machine"
        Write-host "$([Net.ServicePointManager]::SecurityProtocol)" -ForegroundColor Green

    foreach($arcEndpoint in $arcEndpoints.GetEnumerator()){
        Write-Host "Testing access to ARC Connected Machine Agent Endpoint: $($arcEndpoint.name) : $($arcEndpoint.Value) - Result=" -NoNewline
        $response = tnc $arcEndpoint.Value -port 443 
        $color = if($response.TcpTestSucceeded -eq $true){"Green"}else{"Red"}
        write-host "$($response.TcpTestSucceeded)" -ForegroundColor $color
        test-tlsConnectivity -hostname $arcEndpoint 
    }

    Write-host "The following wildcard endpoints can not be tested directly.  Please validate connectivity with your corporate network team"
    foreach($WldCardArcEndpoint in $WldCardArcEndpoints.GetEnumerator()){
        Write-Host "$($WldCardArcEndpoint.name) : $($WldCardArcEndpoint.Value)" -ForegroundColor Yellow
    }
}

function test-tlsConnectivity {
[CmdletBinding()]
    param(
    [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$HostName,
    [Parameter(Mandatory = $false)]
    [UInt16]$Port = 443
    )

    process {

        ##https://learn.microsoft.com/en-us/security/engineering/solving-tls1-problem
        ##https://learn.microsoft.com/en-us/mem/configmgr/core/plan-design/security/enable-tls-1-2-client
        #https://gbeifuss.github.io/p/adding-tls-1.2-support-for-powershell/
        $sslProtocols = “tls”, “tls11”, “tls12”, "tls13"

        foreach($sslProtocol in $sslProtocols) {
            $TcpClient = New-Object Net.Sockets.TcpClient
            $TcpClient.Connect($HostName, $Port)
            $SslStream = New-Object Net.Security.SslStream $TcpClient.GetStream()
            $SslStream.ReadTimeout = 15000
            $SslStream.WriteTimeout = 15000
            try {
                Write-host "Protocol Test: $sslProtocol -" -NoNewline
                $SslStream.AuthenticateAsClient($Hostname,$null,$sslProtocol,$false)
                Write-Host "Succeeded" -ForegroundColor Green
                Write-Verbose "Details: $($env:COMPUTERNAME) ($($TcpClient.client.LocalEndPoint.address.IPAddressToString)) to $hostname ($($TcpClient.client.RemoteEndPoint.address.IPAddressToString):$($TcpClient.client.RemoteEndPoint.port))" -ForegroundColor Green
                Write-Verbose "$($SslStream | select-object SslProtocol, CipherAlgorithm, CipherStrength, HashAlgorithm | Format-Table -AutoSize)"
            } catch [System.IO.IOException] {
                Write-Host "Failed" -ForegroundColor Red
                Write-verbose "- The server does not support the current protocol" 
            } catch [System.Management.Automation.MethodInvocationException] {
                Write-Host "Failed" -ForegroundColor Red
                Write-verbose "- The client and server cannot communicate, because they do not possess a common algorithm" 
            } catch {
                Write-Host "Failed" -ForegroundColor Red
                Write-Verbose $_
            }

        }

    }
}