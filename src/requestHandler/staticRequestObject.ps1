class StaticRequestObject {
    [System.Net.HttpListenerContext]$HttpContext
    [System.Net.HttpListenerRequest]$HttpRequest
    [System.Uri]$RequestUrl
    [string]$LocalPath # url path without domain
    [string[]]$Paths
    [string]$Body
    [System.Collections.Specialized.NameValueCollection]$UrlVariables
    [PSCustomObject]$Settings

    [string]$ContextPath
    [string]$RequestType
    
    StaticRequestObject([System.Net.HttpListener] $listener) {
        $this.Initialize($listener.GetContext())
    }

    StaticRequestObject([System.Net.HttpListenerContext]$context) {
        $this.Initialize($context)
    }

    [void]Initialize([System.Net.HttpListenerContext]$context) {
        $this.HttpContext = $context        
        $this.HttpRequest = $this.HttpContext.Request
        $this.RequestUrl = $this.HttpContext.Request.Url
        $this.LocalPath = ($this.RequestUrl.LocalPath -replace "//", "/") -replace "/$", ""
        $this.Paths = $this.LocalPath -Split '/'
        $this.Body = Get-JsonFromBody($this.HttpRequest)
        $this.UrlVariables = $this.HttpRequest.QueryString

        $settingsFilePath = "./settings.json"
        if (Test-Path -LiteralPath $settingsFilePath) {
            $this.Settings = Get-Content $settingsFilePath | ConvertFrom-Json
        } else {
            $this.Settings = [PSCustomObject]@{
                webFolder = "./"
            }
        }

        $this.RequestType = ""

        Write-Host "url" $this.RequestUrl
        Write-Host "referrer" $this.HttpRequest.Headers["Referer"]
        Write-Host "accept" $this.HttpRequest.Headers["Accept"]
        Write-Host "user agent" $this.HttpRequest.UserAgent

        # First try direct path from script root
        $directPath = Join-Path -Path $Global:RootPath -ChildPath $this.LocalPath.TrimStart('/')
        if (Test-Path -LiteralPath $directPath -PathType Leaf) {
            Write-Host "File resource found at: $directPath"
            $this.RequestType = "File"
            $this.ContextPath = $directPath
            return
        }

        # Then try webroot path
        $webRootPath = $this.Settings.webFolder
        if (-not [System.IO.Path]::IsPathRooted($webRootPath)) {
            $webRootPath = Join-Path -Path $Global:RootPath -ChildPath $webRootPath
        }
        
        $webFilePath = Join-Path -Path $webRootPath -ChildPath $this.LocalPath.TrimStart('/')
        if (Test-Path -LiteralPath $webFilePath -PathType Leaf) {
            Write-Host "File resource found at: $webFilePath"
            $this.RequestType = "File"
            $this.ContextPath = $webFilePath
            return
        }
    }

    RouteRequest() {
        # /favicon.ico
        # /styles/style.css
        if ($this.RequestType -eq "File") {
            Write-Host "File resource"
            # If file exists on path file mode is handled by the binary handler
            BinaryHandler $this
            return
        }
    }
}

