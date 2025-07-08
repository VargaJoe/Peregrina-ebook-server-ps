class BinaryHandler {
    [PSCustomObject]$response
    
    BinaryHandler($requestObject) {
        # Check if we're running in async mode (ResponseObjectAsync available) or sync mode
        if ("ResponseObjectAsync" -as [type]) {
            $this.response = New-Object -TypeName "ResponseObjectAsync" -ArgumentList $requestObject.HttpContext.Response
            Write-Host "Using ResponseObjectAsync for binary response"
        } else {
            $this.response = New-Object -TypeName "ResponseObject" -ArgumentList $requestObject.HttpContext.Response
            Write-Host "Using ResponseObject for binary response"
        }

        $this.response.ResponseType = "binary"
        
        # Handle the file based on request type
        if ($requestObject.RequestType -eq "File") {
            $this.GetPhysicalFile($requestObject)
        } elseif ($requestObject.RequestType -eq "Virtual") {
            $this.GetVirtualFile($requestObject)
        }
    }

    [void] GetPhysicalFile($requestObject) {
        Write-Host "BinaryHandler"
        
        $fullPath = $requestObject.ContextPath
        Write-Host "abs" $fullPath

        # Set content type based on file extension
        $extension = [System.IO.Path]::GetExtension($fullPath)
        $this.response.ContentType = switch ($extension.ToLower()) {
            ".css"  { "text/css" }
            ".js"   { "application/javascript" }
            ".jpg"  { "image/jpeg" }
            ".jpeg" { "image/jpeg" }
            ".png"  { "image/png" }
            ".gif"  { "image/gif" }
            ".ico"  { "image/x-icon" }
            ".pdf"  { "application/pdf" }
            default { "application/octet-stream" }
        }

        # Clear any existing response data
        $this.response.ResponseString = $null
        $this.response.ResponseBytes = $null
        
        # Set the file path for the response to handle
        $this.response.FilePath = $fullPath
        
        # Send the response
        $this.response.Respond()
    }

    [void] GetVirtualFile($requestObject) {
        Write-Host "VirtualBinaryHandler"

        if ($requestObject.VirtualPath) { 
            $selectedFile = $requestObject.VirtualPath.TrimStart('/')
            $zipFile = $null
            $stream = $null
            $reader = $null
    
            try {
                $zipFile = [System.IO.Compression.ZipFile]::OpenRead($requestObject.ContextPath)
                $entry = $zipFile.GetEntry($selectedFile)
                
                if ($null -eq $entry) {
                    Write-Host "File '$selectedFile' not found in zip file."
                    $this.response.HttpResponse.StatusCode = 404
                    $this.response.Respond()
                    return
                }
    
                $filename = $entry.Name
                $extension = [System.IO.Path]::GetExtension($filename)
                $this.response.ContentType = switch ($extension.ToLower()) {
                    ".jpg"  { "image/jpeg" }
                    ".jpeg" { "image/jpeg" }
                    ".png"  { "image/png" }
                    ".gif"  { "image/gif" }
                    ".html" { "text/html" }
                    ".css"  { "text/css" }
                    ".js"   { "application/javascript" }
                    default { "application/octet-stream" }
                }
    
                $stream = $entry.Open()
                $reader = New-Object System.IO.BinaryReader($stream)
                $this.response.ResponseBytes = $reader.ReadBytes([int]$entry.Length)
            } finally {
                if ($null -ne $reader) {
                    $reader.Close()
                }
                
                if ($null -ne $stream) {
                    $stream.Close()
                }
            
                if ($null -ne $zipFile) {
                    $zipFile.Dispose()
                }
            }
        } else { 
            $this.response.ResponseBytes = $null
            $this.response.ResponseString = $null
            $this.response.FilePath = $null
            $this.response.HttpResponse.StatusCode = 404
        }
        
        $this.response.Respond()
    }
}