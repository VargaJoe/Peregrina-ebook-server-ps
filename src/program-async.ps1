param (
    [int]$ServicePort = 8889,
    [switch]$Debug = $true
)

function New-ScriptBlockCallback 
    {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
        param(
            [parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [scriptblock]$Callback
        )

        # Is this type already defined?
        if (-not ( 'CallbackEventBridge' -as [type])) {
            Add-Type @' 
                using System; 
                public sealed class CallbackEventBridge { 
                    public event AsyncCallback CallbackComplete = delegate { }; 
                    private CallbackEventBridge() {} 
                    private void CallbackInternal(IAsyncResult result) { 
                        CallbackComplete(result); 
                    } 
                    public AsyncCallback Callback { 
                        get { return new AsyncCallback(CallbackInternal); } 
                    } 
                    public static CallbackEventBridge Create() { 
                        return new CallbackEventBridge(); 
                    } 
                } 
'@
        }
        $bridge = [callbackeventbridge]::create()
        Register-ObjectEvent -InputObject $bridge -EventName callbackcomplete -Action $Callback -MessageData $args > $null
        $bridge.Callback
    }

# Add debug logging function
function Write-DebugLog {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet('INFO', 'WARNING', 'ERROR', 'DEBUG')]
        [string]$Level = 'INFO'
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - [$Level] $Message" | Out-File -Append -FilePath "./debug-log.txt"
    
    switch ($Level) {
        'ERROR' { 
            Write-Host "[ERROR] $Message" -ForegroundColor Red 
        }
        'WARNING' { 
            Write-Host "[WARNING] $Message" -ForegroundColor Yellow 
        }
        'DEBUG' { 
            Write-Host "[DEBUG] $Message" -ForegroundColor Gray 
        }
        default { 
            Write-Host "[INFO] $Message" 
        }
    }
}

# Clear any existing debug logs
if (Test-Path -Path "./debug-log.txt") {
    Clear-Content -Path "./debug-log.txt"
}

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

# First load the cancellation handler - this MUST be first
Write-DebugLog "Loading cancellation handler..." -Level 'INFO'
. "$PSScriptRoot\utils\cancellation-handler.ps1"

# Load the async ResponseObject implementation
Write-DebugLog "Loading async ResponseObject implementation..." -Level 'INFO'
. "$PSScriptRoot\requestHandler\responseObject-async.ps1"

# Create an alias for ResponseObject pointing to ResponseObjectAsync
if (-not ([System.Management.Automation.PSTypeName]'ResponseObject').Type) {
    Write-DebugLog "Creating ResponseObject alias for ResponseObjectAsync..." -Level 'INFO'
    New-Alias -Name ResponseObject -Value ResponseObjectAsync -Scope Global
}

# Then other utility files
Write-DebugLog "Loading other utility files..." -Level 'INFO'
. "$PSScriptRoot\utils\file-handler.ps1"
. "$PSScriptRoot\utils\helper-functions.ps1"
. "$PSScriptRoot\utils\view-handler.ps1"

# Then load request handler files - order matters!
Write-DebugLog "Loading request handler files..." -Level 'INFO'
. "$PSScriptRoot\requestHandler\binaryHandlerObject.ps1"
. "$PSScriptRoot\requestHandler\staticRequestObject.ps1"
. "$PSScriptRoot\requestHandler\controllerRequestObject.ps1"
. "$PSScriptRoot\requestHandler\errorRequestObject.ps1"
. "$PSScriptRoot\requestHandler\peregrinaRequestObject.ps1"

# Then load models
Write-DebugLog "Loading model files..." -Level 'INFO'
Get-ChildItem -LiteralPath "$PSScriptRoot\models" -Filter *.ps1 | ForEach-Object {
    . $_.FullName
}

# Then load actions
Write-DebugLog "Loading action files..." -Level 'INFO'
Get-ChildItem -LiteralPath "$PSScriptRoot\actions" -Filter *.ps1 | ForEach-Object {
    . $_.FullName
}

# Check if indexHandler folder exists before trying to load from it
if (Test-Path -Path "$PSScriptRoot\indexHandler") {
    Write-DebugLog "Loading index handler files..." -Level 'INFO'
    Get-ChildItem -LiteralPath "$PSScriptRoot\indexHandler" -Filter *.ps1 | ForEach-Object {
        . $_.FullName
    }
}

# Finally load controllers
Write-DebugLog "Loading controller files..." -Level 'INFO'
Get-ChildItem -LiteralPath "$PSScriptRoot\controllers" -Filter *.ps1 | ForEach-Object {
    . $_.FullName
}

# Verify required types are loaded
$asyncReady = $true

if (-not ("CancellationManager" -as [type])) {
    Write-DebugLog "ERROR: CancellationManager type not loaded correctly. Async functions will not work properly." -Level 'ERROR'
    $asyncReady = $false
}

if (-not ("AsyncHelper" -as [type])) {
    Write-DebugLog "ERROR: AsyncHelper type not loaded correctly. Async functions will not work properly." -Level 'ERROR'
    $asyncReady = $false
}

if (-not ("ResponseObjectAsync" -as [type])) {
    Write-DebugLog "ERROR: ResponseObjectAsync type not loaded correctly. Async functions will not work properly." -Level 'ERROR'
    $asyncReady = $false
}

if (-not $asyncReady) {
    Write-DebugLog "WARNING: Server will run in synchronous mode due to missing dependencies." -Level 'WARNING'
}

$Global:JsonResult = $null
$Global:RootPath = $PSScriptRoot
$Global:responseClosed = $true
$Global:CleanupInterval = 30 # Cleanup interval in seconds
$Global:LastCleanupTime = Get-Date
$Global:RequestCount = 0
$Global:ErrorCount = 0

# Try to find an available port if not running as admin
if (-not $isAdmin) {
    $availablePort = Find-AvailablePort -StartPort $ServicePort
    if ($availablePort -ne $ServicePort) {
        Write-Host "Port $ServicePort is not available. Using port $availablePort instead."
        $ServicePort = $availablePort
    }
}

Write-DebugLog "Start Peregrina Webserver on Port $($ServicePort)" -Level 'INFO'
"new listener" | Out-File -Append -FilePath "./log.txt"

# Create HTTP listener
$HttpListener = New-Object System.Net.HttpListener

# Try to use localhost prefix if not admin
if ($isAdmin) {
    # If running as admin, listen on all interfaces
    $prefix = "http://+:$($ServicePort)/"
    Write-DebugLog "Running as administrator, listening on all interfaces" -Level 'INFO'
} else {
    # If not running as admin, listen only on localhost
    $prefix = "http://localhost:$($ServicePort)/"
    Write-DebugLog "Not running as administrator, listening only on localhost" -Level 'INFO'
}

$HttpListener.Prefixes.Add($prefix)

try {
    Write-DebugLog "Trying to start listener on $($prefix)" -Level 'INFO'
    $HttpListener.Start()
    Write-Host "Server started successfully on $($prefix)"

    Write-DebugLog "Preparing async request listener" -Level 'INFO'
    $requestListener = {
            [cmdletbinding()]
            param($result)

            [System.Net.HttpListener]$HttpListener = $result.AsyncState;
            try {
                $context = $HttpListener.EndGetContext($result);    # wait for request to complete
                $Global:RequestCount++
                $Global:responseClosed = $false

                # Generate unique request ID for logging
                $requestId = [guid]::NewGuid().ToString("N").Substring(0, 8)
                
                # Log basic information about the request
                Write-DebugLog "[$requestId] Processing request for: $($context.Request.RawUrl)" -Level 'DEBUG'

                if (-not $Global:responseClosed) {
                    Write-DebugLog "[$requestId] Handling with StaticRequestObject" -Level 'DEBUG'
                    $requestObject = [StaticRequestObject]::new($context)
                    $requestObject.RouteRequest()
                }

                if (-not $Global:responseClosed) {
                    Write-DebugLog "[$requestId] Handling with ControllerRequestObject" -Level 'DEBUG'
                    $requestObject = [ControllerRequestObject]::new($context)
                    $requestObject.RouteRequest()
                }

                if (-not $Global:responseClosed) {
                    Write-DebugLog "[$requestId] Handling with peregrinaRequestObject" -Level 'DEBUG'
                    $requestObject = [peregrinaRequestObject]::new($context)
                    $requestObject.RouteRequest()
                }

                if (-not $Global:responseClosed) {
                    Write-DebugLog "[$requestId] Handling with ErrorRequestObject" -Level 'DEBUG'
                    $requestObject = [ErrorRequestObject]::new($context)
                    $requestObject.RouteRequest()
                }
                
                Write-DebugLog "[$requestId] Request processed successfully" -Level 'DEBUG'
            }
            catch {
                $Global:ErrorCount++
                Write-DebugLog "Error processing request: $_" -Level 'ERROR'
                Write-DebugLog "Stack trace: $($_.ScriptStackTrace)" -Level 'ERROR'
                try {
                    if ($context -and $context.Response) {
                        $context.Response.StatusCode = 500
                        $context.Response.Close()
                    }
                }
                catch {
                    Write-DebugLog "Error closing response: $_" -Level 'ERROR'
                }
                $Global:responseClosed = $true
            }
            finally {
                # Always make sure we set up the next request
                try {
                    if ($HttpListener.IsListening) {
                        $HttpListener.BeginGetContext((New-ScriptBlockCallback -Callback $requestListener), $HttpListener) | Out-Null
                    }
                }
                catch {
                    Write-DebugLog "Error setting up next request: $_" -Level 'ERROR'
                }
            }
    } 

    # Start the first async request
    $context = $HttpListener.BeginGetContext((New-ScriptBlockCallback -Callback $requestListener), $HttpListener)
    Write-DebugLog "Server is accepting requests on port $ServicePort" -Level 'INFO'
    
    # Show URL in console
    Write-Host "`n"
    Write-Host "========================================"
    Write-Host "Server is running at: $($prefix)"
    Write-Host "Open this URL in your browser to access the server"
    Write-Host "Press Ctrl+C to stop the server"
    Write-Host "========================================"
    Write-Host "`n"

    # Track server stats
    $serverStartTime = Get-Date
    [datetime]$timestamp = Get-Date
    [long]$count = 60

    $stopFile = "./appoffline.htm"

    While ($HttpListener.IsListening -and !(Test-Path -Path $stopFile)) {
        $Global:responseClosed = $false
        
        # Display activity indicator
        if ($count -ge 60) {
            $uptime = (Get-Date) - $serverStartTime
            $activeRequests = 0
            
            if ($asyncReady) {
                try {
                    $activeRequests = [CancellationManager]::ActiveRequestCount()
                } catch {
                    # Ignore exceptions in stats gathering
                }
            }
            
            Write-Host "$(([System.DateTime]::UtcNow).tostring("u")) | " -NoNewLine
            Write-Host "Uptime: $($uptime.ToString('dd\.hh\:mm\:ss')) | " -NoNewLine
            Write-Host "Req: $Global:RequestCount | Err: $Global:ErrorCount | Active: $activeRequests      " -NoNewLine
            Write-Host "`r" -NoNewLine
            
            $count=0
        }
        if (((get-date) - $timestamp).totalseconds -gt 1) {
            write-host "." -NoNewline        
            $count++
            $timestamp = Get-date
        }

        # Perform periodic cleanup of cancelled requests
        $currentTime = Get-Date
        if (($currentTime - $Global:LastCleanupTime).TotalSeconds -gt $Global:CleanupInterval) {
            Write-DebugLog "Cleaning up cancelled requests..." -Level 'DEBUG'
            
            if ("CancellationManager" -as [type]) {
                try {
                    [CancellationManager]::CleanupOldRequests()
                }
                catch {
                    Write-DebugLog "Error during cleanup: $_" -Level 'ERROR'
                }
            }
            
            $Global:LastCleanupTime = $currentTime
        }

        # Small delay to prevent high CPU usage
        Start-Sleep -Milliseconds 100
    }
}
catch {
    Write-DebugLog "Error starting server: $_" -Level 'ERROR'
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
            Write-DebugLog "Error stopping listener: $_" -Level 'ERROR'
        }
        
        try {
            $HttpListener.Close()
        }
        catch {
            Write-DebugLog "Error closing listener: $_" -Level 'ERROR'
        }
    }
    
    Write-DebugLog "Stop Peregrina Webserver" -Level 'INFO'
    "stop listener" | Out-File -Append -FilePath "./log.txt"
}