class PdfModelObject {
    [PSCustomObject]$model = @{}

    PdfModelObject($requestObject) {
        # Get the current page number from query parameters, default to 1
        $currentPage = 1
        if ($requestObject.queryParameters -and $requestObject.queryParameters.ContainsKey("page")) {
            try {
                $currentPage = [int]$requestObject.queryParameters["page"]
                if ($currentPage -lt 1) { $currentPage = 1 }
            } catch {
                $currentPage = 1
            }
        }

        # Build model with additional page navigation properties
        $this.model = @{
            type = "file"
            category = "pdf"
            url = $requestObject.localPath
            currentPage = $currentPage
            rawPdfUrl = $requestObject.localPath
            viewerMode = "embedded" # could be "embedded", "download", or "pdf.js"
            requestPath = $requestObject.path
        }
    }
}