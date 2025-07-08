function Show-View {
    param(
        [parameter(Mandatory = $true)]
        [Object]$response,
        [parameter(Mandatory = $true)]
        [string]$viewName,
        [parameter(Mandatory = $false)]
        [Object]$model
    )
    
    $response.ResponseType = "html"
    
    # Create a clean scope for template evaluation
    $templateScope = [PSCustomObject]@{
        model = $model
        response = $response
        viewName = $viewName
    }

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
    $viewTemplate = (Get-Content -LiteralPath $templatePath -Raw)

    # Define a regular expression pattern to match PowerShell snippets within <% ... %>
    $pattern = '<%\s*([\s\S]*?)\s*%>'
    $regex = [regex]::new($pattern)

    # Process the template
    $evaluatedFragments = @()
    $lastIndex = 0
    
    foreach ($match in $regex.Matches($viewTemplate)) {
        # Add text before the match
        if ($match.Index -gt $lastIndex) {
            $evaluatedFragments += $viewTemplate.Substring($lastIndex, $match.Index - $lastIndex)
        }
        
        # Extract and evaluate the code snippet
        $codeSnippet = $match.Groups[1].Value
        Write-Host "matched: $codeSnippet"
        
        try {
            # Create script block with explicit variable import
            $scriptBlock = {
                param($templateScope)
                $model = $templateScope.model
                
                # Execute the template code
                Invoke-Expression $args[0]
            }
            
            # Execute script block with proper scope
            $evaluatedSnippet = & $scriptBlock $templateScope $codeSnippet
            
            if ($null -eq $evaluatedSnippet) {
                $evaluatedSnippet = ""
            }
            elseif ($evaluatedSnippet -is [array]) {
                $evaluatedSnippet = $evaluatedSnippet -join ""
            }
            
            $evaluatedFragments += $evaluatedSnippet
        }
        catch {
            $evaluatedFragments += "<!-- Error processing template code: $_ -->"
            Write-Host "Error evaluating script block: $_"
        }
        
        # Update lastIndex for next iteration
        $lastIndex = $match.Index + $match.Length
    }
    
    # Add any remaining template text
    if ($lastIndex -lt $viewTemplate.Length) {
        $evaluatedFragments += $viewTemplate.Substring($lastIndex)
    }
    
    # Combine all fragments into the final HTML
    $evaluatedView = $evaluatedFragments -join ""

    # Send the response
    $response.ResponseString = $evaluatedView
    $response.Respond()
    Write-Host "done"
}