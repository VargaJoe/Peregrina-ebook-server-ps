class pdfModelObject {
    [PSObject]$model
    [string]$pdfPath
    [string]$currentPage

    pdfModelObject($requestObject) {
        Write-AppLog "Creating pdfModelObject for path: $($requestObject.ContextPath)" -Source "PDF-Model" -Level "INFO"
        $this.pdfPath = $requestObject.ContextPath
        
        # Build the PDF viewer model
        $this.model = [PSCustomObject]@{
            type = "pdf"
            title = [System.IO.Path]::GetFileNameWithoutExtension($this.pdfPath)
            path = $this.pdfPath 
        }
        
        # Get current page from URL variables if available
        if ($requestObject.UrlVariables -ne $null -and $requestObject.UrlVariables["page"] -ne $null) {
            Write-AppLog "Found page parameter: $($requestObject.UrlVariables["page"])" -Source "PDF-Model" -Level "INFO"
            $this.currentPage = $requestObject.UrlVariables["page"]
            $this.model | Add-Member -MemberType NoteProperty -Name "currentPage" -Value $this.currentPage
        } else {
            Write-AppLog "No page parameter found in URL variables" -Source "PDF-Model" -Level "INFO" 
            $this.model | Add-Member -MemberType NoteProperty -Name "currentPage" -Value 1
        }
        
        # Get raw mode parameter - this is important for direct PDF download
        $rawMode = $false
        if ($requestObject.UrlVariables -ne $null -and 
            ($requestObject.UrlVariables["raw"] -eq "true" -or $requestObject.UrlVariables["raw"] -eq "True")) {
            Write-AppLog "Raw mode requested via URL parameter" -Source "PDF-Model" -Level "INFO"
            $rawMode = $true
        }
        
        # Build the raw PDF URL (for direct access/download)
        $pdfUrl = $requestObject.VirtualPath
        if (-not $rawMode) {
            if ($pdfUrl.Contains("?")) {
                $pdfUrl = "$($pdfUrl)&raw=true"
            } else {
                $pdfUrl = "$($pdfUrl)?raw=true"  
            }
        }
        
        Write-AppLog "Raw PDF URL: $pdfUrl" -Source "PDF-Model" -Level "INFO"
        $this.model | Add-Member -MemberType NoteProperty -Name "rawPdfUrl" -Value $pdfUrl
        
        # Add a version identifier to verify which template version is loaded
        $this.model | Add-Member -MemberType NoteProperty -Name "viewerVersion" -Value "v3.0-debug"
        
        # Add htmlId property to match the reference in the JavaScript
        $this.model | Add-Member -MemberType NoteProperty -Name "htmlId" -Value "pdf-$([guid]::NewGuid().ToString('N').Substring(0,8))"
        
        # Log the complete model for debugging
        Write-AppLog "PDF Model created: $($this.model | ConvertTo-Json -Depth 3)" -Source "PDF-Model" -Level "DEBUG"
    }
}