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
            Write-Host "Details: $($env:COMPUTERNAME) ($($TcpClient.client.LocalEndPoint.address.IPAddressToString)) to $hostname ($($TcpClient.client.RemoteEndPoint.address.IPAddressToString):$($TcpClient.client.RemoteEndPoint.port))" -ForegroundColor Green
            $SslStream | select-object SslProtocol, CipherAlgorithm, CipherStrength, HashAlgorithm | Format-Table -AutoSize
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