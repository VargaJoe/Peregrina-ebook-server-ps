function Show-View {
    param(
        # [parameter(Mandatory = $true)]
        # [peregrinaRequestObject]$requestObject,
        [parameter(Mandatory = $true)]
        [ResponseObject]$response,
        [parameter(Mandatory = $true)]
        [string]$viewName,
        [parameter(Mandatory = $false)]
        [Object]$model
    )
    # "new response $viewName" | Out-File -Append -FilePath "./log.txt"
    # $response = [ResponseObject]::new($requestObject.HttpContext.Response)
    $response.ResponseType = "html"

    # Determine if we should use a specific template based on model type
    $templatePath = "./views/$viewName.pshtml"
    
    # If the model has a 'type' property, check if there's a view template matching that type
    if ($model -and $model.type) {
        $modelTypePath = "./views/$($model.type).pshtml"
        Write-Host "Checking for model-specific template: $modelTypePath"
        if (Test-Path -LiteralPath $modelTypePath) {
            Write-Host "Found model-specific template for type: $($model.type)"
            $templatePath = $modelTypePath
        } else {
            Write-Host "No model-specific template found for type: $($model.type), using default: $templatePath"
        }
    }

    # Read the HTML content from the file
    if (-not (Test-Path -LiteralPath $templatePath)) {
        Write-Host "Warning: Template not found at $templatePath, falling back to home template"
        $templatePath = "./views/home.pshtml"
    }
    
    Write-Host "Using template: $templatePath"
    $viewTemplate = (Get-Content -LiteralPath $templatePath -Raw) #-Replace '"', '&quot;'
    # $evaluatedView = (Invoke-Expression "`"$viewTemplate`"") -Replace '&quot;', '"'    

    # Define a regular expression pattern to match PowerShell snippets within $( ... )
    $pattern = '<%\s*([\s\S]*?)\s*%>'

    # Use a regular expression match evaluator to evaluate PowerShell snippets
    # Create a regex object
    $regex = [regex]::new($pattern)

    # Initialize an array to store evaluated results
    $evaluatedSnippets = @()

    # Store the matches and their indices
    $matchIndices = @()
    foreach ($match in $regex.Matches($viewTemplate)) {
        $codeSnippet = $match.Groups[1].Value  # Access the matched code snippet
        Write-Host "matched: $codeSnippet"
        # Evaluate the code snippet
        try {
        $evaluatedSnippet = Invoke-Expression $codeSnippet
        } catch {
            $evaluatedSnippet = "Error: $_"
        }
        if ($evaluatedSnippet -is [array]) {
            $evaluatedSnippet = $evaluatedSnippet -join " "
        }
        # Write-Host "evaluated: $evaluatedSnippet"
        $evaluatedSnippets += $evaluatedSnippet
        $matchIndices += $match.Index
    }

    # Replace the matched patterns with the evaluated results
    $evaluatedView = $regex.Replace($viewTemplate, {
        param($match)
        $index = [array]::IndexOf($matchIndices, $match.Index)
        $evaluatedSnippet = $evaluatedSnippets[$index]  # Use the match index to get the evaluated snippet
        return $evaluatedSnippet
    })

    # Evaluated HTML content goes to response
    $response.ResponseString = $evaluatedView
    $response.Respond()
    write-host done
}