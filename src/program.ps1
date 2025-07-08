# Use the following commands to bind/unbind SSL cert
# netsh http add sslcert ipport=0.0.0.0:443 certhash=3badca4f8d38a85269085aba598f0a8a51f057ae "appid={00112233-4455-6677-8899-AABBCCDDEEFF}"
# netsh http delete sslcert ipport=0.0.0.0:443 

param (
    [int]$ServicePort = 8888
)

# Function to check if a port is available
function Test-PortAvailable {
    param (
        [int]$Port
    )
    
    try {
        $tcpClient = New-Object System.Net.Sockets.TcpClient
        $result = $tcpClient.BeginConnect("127.0.0.1", $Port, $null, $null)
        $success = $result.AsyncWaitHandle.WaitOne(100, $true)
        
        if ($success) {
            # Port is in use
            $tcpClient.Close()
            return $false
        } else {
            # Port is available
            $tcpClient.Close()
            return $true
        }
    }
    catch {
        # Error checking port - assume it's available
        return $true
    }
}

# Function to find an available port
function Find-AvailablePort {
    param (
        [int]$StartPort = 8888,
        [int]$MaxTries = 10
    )
    
    $port = $StartPort
    $found = $false
    $tries = 0
    
    while (-not $found -and $tries -lt $MaxTries) {
        if (Test-PortAvailable -Port $port) {
            $found = $true
            return $port
        }
        
        $port++
        $tries++
    }
    
    # If we couldn't find a port, return a high random port
    return (Get-Random -Minimum 10000 -Maximum 65000)
}

# Check if running as admin
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")

# Load helper functions from the Utils folder
Get-ChildItem -LiteralPath ./models -Filter *.ps1 | ForEach-Object {
    . $_.FullName
}

Get-ChildItem -LiteralPath ./actions -Filter *.ps1 | ForEach-Object {
    . $_.FullName
}

# Load request handler files selectively to avoid loading the async versions
Write-Host "Loading synchronous request handler files..."
. "$PSScriptRoot\requestHandler\responseObject.ps1"
. "$PSScriptRoot\requestHandler\binaryHandlerObject.ps1"
. "$PSScriptRoot\requestHandler\staticRequestObject.ps1"
. "$PSScriptRoot\requestHandler\controllerRequestObject.ps1"
. "$PSScriptRoot\requestHandler\errorRequestObject.ps1"
. "$PSScriptRoot\requestHandler\peregrinaRequestObject.ps1"

# Load utility files but exclude the async-specific ones
Get-ChildItem -LiteralPath ./utils -Filter *.ps1 | Where-Object { $_.Name -ne "cancellation-handler.ps1" } | ForEach-Object {
    . $_.FullName
}

# Load controllers from the Controllers folder
Get-ChildItem -LiteralPath ./controllers -Filter *.ps1 | ForEach-Object {
    . $_.FullName
}

$Global:JsonResult = $null
$Global:RootPath = $PSScriptRoot
$Global:responseClosed = $true

# Try to find an available port if not running as admin
if (-not $isAdmin) {
    $availablePort = Find-AvailablePort -StartPort $ServicePort
    if ($availablePort -ne $ServicePort) {
        Write-Host "Port $ServicePort is not available. Using port $availablePort instead."
        $ServicePort = $availablePort
    }
}

"new listener" | Out-File -Append -FilePath "./log.txt"
$HttpListener = New-Object System.Net.HttpListener

# Try to use localhost prefix if not admin
if ($isAdmin) {
    # If running as admin, listen on all interfaces
    $prefix = "http://+:$($ServicePort)/"
    Write-Host "Running as administrator, listening on all interfaces"
    $HttpListener.Prefixes.Add($prefix)
    
    # Only add HTTPS binding if running as admin
    $HttpListener.Prefixes.Add("https://+:443/")
} else {
    # If not running as admin, listen only on localhost
    $prefix = "http://localhost:$($ServicePort)/"
    Write-Host "Not running as administrator, listening only on localhost"
    $HttpListener.Prefixes.Add($prefix)
}

try {
    Write-Host "Trying to start listener on $($prefix)"
    $HttpListener.Start()
    Write-Host "Server started successfully on $($prefix)"
    
    # Show URL in console
    Write-Host "`n"
    Write-Host "========================================"
    Write-Host "Server is running at: $($prefix)"
    Write-Host "Open this URL in your browser to access the server"
    Write-Host "Press Ctrl+C to stop the server"
    Write-Host "========================================"
    Write-Host "`n"
    
    $stopFile = "./appoffline.htm"

    While ($HttpListener.IsListening -and !(Test-Path -Path $stopFile)) {
        $Global:responseClosed = $false
        $context = $HttpListener.GetContext()
                
        # context variables
        if (-not $Global:responseClosed) {
            Write-Host "StaticRequestObject"
            $requestObject = [StaticRequestObject]::new($context)
            $requestObject.RouteRequest()
        }
        
        if (-not $Global:responseClosed) {
            Write-Host "ControllerRequestObject"
            $requestObject = [ControllerRequestObject]::new($context)
            $requestObject.RouteRequest()
        }

        if (-not $Global:responseClosed) {
            Write-Host "peregrinaRequestObject"
            $requestObject = [peregrinaRequestObject]::new($context)
            $requestObject.RouteRequest()
        }

        if (-not $Global:responseClosed) {
            Write-Host "ErrorRequestObject"
            $requestObject = [ErrorRequestObject]::new($context)
            $requestObject.RouteRequest()
        }
    }
}
catch {
    Write-Host "Error starting server: $_" -ForegroundColor Red
    
    if (-not $isAdmin -and $_.Exception.Message -like "*Access is denied*") {
        Write-Host "`nThis may be due to insufficient permissions. Try:" -ForegroundColor Yellow
        Write-Host "1. Running PowerShell as Administrator, or" -ForegroundColor Yellow
        Write-Host "2. Using a different port above 1024 (e.g., powershell -File $PSCommandPath -ServicePort 8080)" -ForegroundColor Yellow
    }
}
finally {
    if ($HttpListener -ne $null -and $HttpListener.IsListening) {
        try {
            $HttpListener.Stop()
        }
        catch {
            Write-Host "Error stopping listener: $_"
        }
        
        try {
            $HttpListener.Close()
        }
        catch {
            Write-Host "Error closing listener: $_"
        }
    }
    
    "stop listener" | Out-File -Append -FilePath "./log.txt"
}