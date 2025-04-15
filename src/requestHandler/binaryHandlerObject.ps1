class BinaryHandler {
    [PSCustomObject]$response

    BinaryHandler($requestObject) {
        $typeName = "ResponseObject"
        if ([System.Management.Automation.PSTypeName]$typeName) {
            $this.response = New-Object -TypeName $typeName -ArgumentList $requestObject.HttpContext.Response
        }

        # Set the initial response type to binary
        $this.response.ResponseType = "binary"
    }

    [void] GetPhysicalFile($requestObject) {
        Write-Host "GetPhysicalFile"
        try {
            Show-Context
            $fullPath = $requestObject.ContextPath            

            # Check if the file exists
            if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
                Write-Host "File not found: $fullPath"
                $this.response.HttpResponse.StatusCode = 404
                $this.response.Respond()
                return
            }

            $this.response.ContentType = Get-MimeType -filePath $fullPath

            # Check if it's a PDF file
            if ($this.response.ContentType -eq 'application/pdf') {
                # Check if pdfimages is available
                if (!(Get-Command -Name pdfimages -ErrorAction SilentlyContinue)) {
                    $this.response.HttpResponse.StatusCode = 500
                    $this.response.ContentType = "application/json"
                    $this.response.content = ConvertTo-Json -InputObject @{ error = "pdfimages command not found." }
                    $this.response.Respond()
                    return
                }

                # Create a temporary directory for images
                $tempDir = Join-Path -Path (Split-Path $fullPath) -ChildPath "temp-pdf-images"
                if (!(Test-Path -Path $tempDir)) {
                    New-Item -ItemType Directory -Path $tempDir | Out-Null
                }
                
                # Generate image file names
                $pdfFileName = [System.IO.Path]::GetFileNameWithoutExtension($fullPath)
                $imageFileBase = Join-Path -Path $tempDir -ChildPath "$pdfFileName"

                # Convert PDF pages to images using pdfimages
                & pdfimages -j "$fullPath" "$imageFileBase"
                
                # get generated file paths
                $generatedImages = Get-ChildItem -Path $tempDir -Filter "$pdfFileName-*.jpg" | Sort-Object -Property Name
                # Create an array of image URLs
                $imageUrls = foreach($file in $generatedImages) {
                    "/temp-pdf-images/$($file.Name)"
                }
                
                # Respond with image URLs in JSON format
                $this.response.HttpResponse.StatusCode = 200
                $this.response.ContentType = "application/json"
                $this.response.content = ConvertTo-Json -InputObject @{ imageUrls = $imageUrls }
            } else {
                # Handle other file types as before
                $fileStream = [System.IO.File]::OpenRead($fullPath)
                try {
                    # Stream the file to the response output stream
                    $fileStream.CopyTo($this.response.HttpResponse.OutputStream)
                    $this.response.HttpResponse.StatusCode = 200
                }
                catch {
                    Write-Host "Error sending file: $_"
                    $this.response.HttpResponse.StatusCode = 500
                } finally{
                    $fileStream.Close()
                }
            }
        } catch {
            Write-Host "Error in GetPhysicalFile: $_"
            $this.response.HttpResponse.StatusCode = 500
        } finally {
            $this.response.Respond()
        }
    }

    [void] GetVirtualFile($requestObject) {
        Write-Host "GetVirtualFile"
        try {
            Show-Context

            if (-not $requestObject.VirtualPath) {
                $this.response.HttpResponse.StatusCode = 404
                return
            }

            $selectedFile = $requestObject.VirtualPath.TrimStart('/')
            $zipFile = $null
            $entryStream = $null

            try{
                # Open the ZIP file in read mode
                $zipFile = [System.IO.Compression.ZipFile]::OpenRead($requestObject.ContextPath)
                # Get the requested entry inside the archive
                $entry = $zipFile.GetEntry($selectedFile)

                if ($null -eq $entry) {
                    Write-Host "File '$selectedFile' not found in zip file."
                    $this.response.HttpResponse.StatusCode = 404
                    return
                }

                # get file type
                $this.response.ContentType = Get-MimeType -filePath $entry.Name

                # Open the entry stream for reading
                $entryStream = $entry.Open()
                # Stream the content of the entry to the output stream
                $entryStream.CopyTo($this.response.HttpResponse.OutputStream)
                $this.response.HttpResponse.StatusCode = 200
            }catch{
                Write-Host "Error processing virtual file: $_"
                $this.response.HttpResponse.StatusCode = 500
            }finally {
                if ($null -ne $entryStream){
                    $entryStream.Close()
                }
                if ($null -ne $zipFile) {
                    $zipFile.Dispose()
                }
            }
        } catch {
            Write-Host "Error in GetVirtualFile: $_"
            $this.response.HttpResponse.StatusCode = 500
        } finally {
            $this.response.Respond()
        }
    }
    [void] RouteRequest($requestObject) {
        if ($requestObject.IsContainer -and $requestObject.VirtualPath -ne $null) {
            # Virtual file
            GetVirtualFile $requestObject
        } else {
            # Physical file
            GetPhysicalFile $requestObject
        }
    }
}