function Test-ServerSSLSupport {
[CmdletBinding()]
param(
[Parameter(Mandatory = $true, ValueFromPipeline = $true)]
[ValidateNotNullOrEmpty()]
[string]$HostName,
[UInt16]$Port = 443
)
process {
    $RetValue = New-Object psobject -Property @{
    Host = $HostName
    Port = $Port
    SSLv2 = $false
    SSLv3 = $false
    TLSv1_0 = $false
    TLSv1_1 = $false
    TLSv1_2 = $false
    TLSv1_3 = $false
    KeyExhange = $null
    HashAlgorithm = $null
    }

    “ssl2”, “ssl3”, “tls”, “tls11”, “tls12”, "tls13" | %{
        $TcpClient = New-Object Net.Sockets.TcpClient
        $TcpClient.Connect($RetValue.Host, $RetValue.Port)
        $SslStream = New-Object Net.Security.SslStream $TcpClient.GetStream()
        $SslStream.ReadTimeout = 15000
        $SslStream.WriteTimeout = 15000
        try {
            $SslStream.AuthenticateAsClient($RetValue.Host,$null,$_,$false)
            $RetValue.KeyExhange = $SslStream.KeyExchangeAlgorithm
            $RetValue.HashAlgorithm = $SslStream.HashAlgorithm
            $status = $true
        } catch {
            $status = $false
        }

        switch ($_) {
            “ssl2” {$RetValue.SSLv2 = $status}
            “ssl3” {$RetValue.SSLv3 = $status}
            “tls” {$RetValue.TLSv1_0 = $status}
            “tls11” {$RetValue.TLSv1_1 = $status}
            “tls12” {$RetValue.TLSv1_2 = $status}
            “tls13” {$RetValue.TLSv1_3 = $status}
        }

    # dispose objects to prevent memory leaks
    #$TcpClient.Dispose()
    #$SslStream.Dispose()
    }

    Write-host "Testing TLS/SSL Connectivity to $($RetValue.HostName) on Port $($RetValue.port)"
    Write-host $RetValue.SSLv2
    Write-host $RetValue.SSLv3
    Write-host $RetValue.TLSv1_0
    Write-host $RetValue.TLSv1_1
    Write-host $RetValue.TLSv1_2
    Write-host $RetValue.TLSv1_3
  
    #“From “+ $TcpClient.client.LocalEndPoint.address.IPAddressToString +” to $hostname “+ $TcpClient.client.RemoteEndPoint.address.IPAddressToString +’:’+$TcpClient.client.RemoteEndPoint.port
    #$SslStream |gm |?{$_.MemberType -match ‘Property’}|Select-Object Name |%{$_.Name +’: ‘+ $sslStream.($_.name)}
    }
}