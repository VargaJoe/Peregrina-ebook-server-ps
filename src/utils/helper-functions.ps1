function Get-JsonFromBody {
    param($HttpRequest)

    if($HttpRequest.HasEntityBody) {
        $Reader = New-Object System.IO.StreamReader($HttpRequest.InputStream)
        $json = $Reader.ReadToEnd() | ConvertFrom-Json 
        return $json
    }
}

function Show-Context {
    Write-Host "controller" $($requestObject.Controller)
    Write-Host "category" $($requestObject.Category)
    Write-Host "index" $($requestObject.FolderIndex)
    Write-Host "root" $($requestObject.FolderPath)
    Write-Host "rel" $($requestObject.RelativePath)
    Write-Host "virt" $($requestObject.VirtualPath)
    Write-Host "abs" $($requestObject.ContextPath)
    Write-Host "action" $($requestObject.Action)
}

function Get-MimeType {
    param (
        [Parameter(Mandatory=$true)]
        [string] $filename
    )

    $extension = [System.IO.Path]::GetExtension($filename).ToLower()

    $mimeTypes = @{
        '.txt'  = 'text/plain'
        '.pdf'  = 'application/pdf'
        '.doc'  = 'application/msword'
        '.docx' = 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
        '.xls'  = 'application/vnd.ms-excel'
        '.xlsx' = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
        '.jpg'  = 'image/jpeg'
        '.png'  = 'image/png'
        '.gif'  = 'image/gif'
        '.zip'  = 'application/zip'
        # Add more mappings as needed
    }

    if ($mimeTypes.ContainsKey($extension)) {
        return $mimeTypes[$extension]
    } else {
        return 'application/octet-stream'  # Default MIME type
    }
}

function BinaryHandler($requestObject) {
    $binary = [BinaryHandler]::new($requestObject)
    $binary.GetPhysicalFile($requestObject)
}

function VirtualBinaryHandler($requestObject) {
    $binary = [BinaryHandler]::new($requestObject)
    $binary.GetVirtualFile($requestObject)
}

function PageHandler($requestObject) {
    Write-Host "PageHandler called with RequestType: $($requestObject.RequestType)"
    try {
        Show-Context
        $typeName = $requestObject.ContextModelType + $requestObject.VirtualModelType + "ModelObject"
        Write-Host "type $typeName"
        if ([System.Management.Automation.PSTypeName]$typeName) {
            $pageModel = New-Object -TypeName $typeName -ArgumentList $requestObject
        }
        Write-Host "model type" $pageModel.model.type
        if ($null -eq $pageModel -or $null -eq $pageModel.model -or $pageModel.model.type -eq "error") {
            Write-Host "Model not found or error occured."
            return
        }

        # Ensure we have a non-empty template name, defaulting to "home" if both are empty
        $pageTemplate = if ($requestObject.VirtualModelType) { 
            $requestObject.VirtualModelType 
        } elseif ($requestObject.ModelType) { 
            # $requestObject.ModelType 
            $requestObject.ContextModelType
        } else { 
            "home" # Default template if both are empty
        }
        
        Write-Host "matched: $pageTemplate"
        
        # Check if we're running in async mode (ResponseObjectAsync available) or sync mode
        if ("ResponseObjectAsync" -as [type]) {
            $response = [ResponseObjectAsync]::new($requestObject.HttpContext.Response)
            Write-Host "Using ResponseObjectAsync for response"
        } else {
            $response = [ResponseObject]::new($requestObject.HttpContext.Response)
            Write-Host "Using ResponseObject for response"
        }
        
        Show-View $response $pageTemplate $pageModel.model
    }
    catch {
        Write-Host "Error in PageHandler: $_"
        Write-Host "Stack trace: $($_.ScriptStackTrace)"
    }
}

function ActionHandler($requestObject) {
    Write-Host "ActionHandler called with Action: $($requestObject.Action)"
    try {
        Show-Context
        $typeName = $requestObject.ContextModelType + $requestObject.VirtualModelType + $requestObject.Action + "ModelObject"
        Write-Host "action type $typeName"
        
        if ([System.Management.Automation.PSTypeName]$typeName) {
            try {
                $actionModel = New-Object -TypeName $typeName -ArgumentList $requestObject
            } catch {
                Write-Host "Error creating action model: $_"
                return
            }
        }
        
        # Call the action model's GetResponse method
        # The action model constructor now handles async vs sync mode detection
        $actionModel.GetResponse($requestObject)
    }
    catch {
        Write-Host "Error in ActionHandler: $_"
        Write-Host "Stack trace: $($_.ScriptStackTrace)"
    }
}

function Write-PDFDiagnostics {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        
        [Parameter(Mandatory=$false)]
        [string]$Source = "PDF-Diagnostics",
        
        [Parameter(Mandatory=$false)]
        [ValidateSet("INFO", "WARNING", "ERROR")]
        [string]$Level = "INFO"
    )
    
    # Create timestamp
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    
    # Format the log message
    $logMessage = "[$timestamp] [$Level] [$Source] $Message"
    
    # Log to console
    Write-Host $logMessage
    
    # Log to diagnostics file
    $logFilePath = Join-Path (Split-Path -Parent $PSScriptRoot) "pdf-diagnostics.log"
    Add-Content -Path $logFilePath -Value $logMessage
    
    # For errors, also write to a separate error log
    if ($Level -eq "ERROR") {
        $errorLogPath = Join-Path (Split-Path -Parent $PSScriptRoot) "pdf-errors.log"
        Add-Content -Path $errorLogPath -Value $logMessage
    }
}

# Log messages to a file with timestamp
function Write-AppLog {
    param(
        [Parameter(Mandatory=$true, Position=0)]
        [string]$Message,
        
        [Parameter(Mandatory=$false)]
        [string]$Source = "General",
        
        [Parameter(Mandatory=$false)]
        [string]$LogFile = "./debug-log.txt",
        
        [Parameter(Mandatory=$false)]
        [ValidateSet("INFO", "WARNING", "ERROR", "DEBUG")]
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] [$Source] $Message"
    
    # Append to log file
    Add-Content -Path $LogFile -Value $logEntry
    
    # Also output to console with color based on level
    $color = switch($Level) {
        "ERROR" { "Red" }
        "WARNING" { "Yellow" }
        "DEBUG" { "Cyan" }
        default { "White" }
    }
    
    Write-Host $logEntry -ForegroundColor $color
}
