class ResponseObjectAsync {
    [System.Net.HttpListenerResponse]$HttpResponse
    [string]$FilePath
    [string]$ResponseString
    [byte[]]$ResponseBytes
    [string]$ResponseType
    [string]$ContentType
    [string]$RequestId
    [bool]$IsAsync = $true

    ResponseObjectAsync([System.Net.HttpListenerResponse] $response) {
        $this.HttpResponse = $response
        $this.HttpResponse.Headers.Add("Access-Control-Allow-Origin", "*")
        $this.HttpResponse.Headers.Add("Access-Control-Allow-Headers", "Content-Type")
        $this.HttpResponse.StatusCode = 200
        $this.RequestId = [guid]::NewGuid().ToString()
        
        # Make sure CancellationManager class is available before using it
        if ("CancellationManager" -as [type]) {
            try {
                [CancellationManager]::RegisterRequest($this.RequestId)
            }
            catch {
                $this.IsAsync = $false
                Write-Host "Error registering request: $_"
            }
        }
        else {
            # Fallback to synchronous mode if CancellationManager is unavailable
            $this.IsAsync = $false
            Write-Host "Warning: CancellationManager not available, falling back to synchronous mode"
        }
    }

    [void] Respond() {
        # Only use async if we have the CancellationManager available
        if ($this.IsAsync -and ("CancellationManager" -as [type])) {
            $this.RespondAsync()
            return
        }

        # Fallback to synchronous response
        $ResponseBuffer = @()

        if ($Global:responseClosed) {
            Write-Host "Response is already closed."
            return
        }

        if ([string]::IsNullOrEmpty($this.ContentType)) {
            switch ($this.ResponseType) {
                "json" {
                    $this.ContentType = "application/json"
                }
                "html" {
                    $this.ContentType = "text/html"
                }
                "binary" {
                    $this.ContentType = "application/octet-stream"
                }
                Default {}
            }
        }

        try {
            # Set Content-Type header before writing content
            $this.HttpResponse.Headers.Add("Content-Type", $this.ContentType)
            
            if ($this.ResponseBytes -and $this.ResponseBytes.Length -gt 0) {
                $ResponseBuffer = $this.ResponseBytes
            } elseif ($this.ResponseString -and $this.ResponseString.Length -gt 0) {
                $ResponseBuffer = [System.Text.Encoding]::UTF8.GetBytes($this.ResponseString)
            } elseif ($this.filepath -and (Test-Path -Path $this.FilePath)) {
                $ResponseBuffer = [System.IO.File]::ReadAllBytes($this.FilePath)
            } else {
                $this.HttpResponse.StatusCode = 404
            }

            if ($ResponseBuffer -and $ResponseBuffer.Length -gt 0) {
                $this.HttpResponse.ContentLength64 = $ResponseBuffer.Length
                
                try {
                    $this.HttpResponse.OutputStream.Write($ResponseBuffer, 0, $ResponseBuffer.Length)
                    $this.HttpResponse.OutputStream.Close()
                } catch {
                    Write-Host "Error writing to OutputStream: $_"
                }
            }         
        } catch {
            Write-Host "Error in synchronous respond: $_"
            $this.HttpResponse.StatusCode = 500
        } finally {
            try {
                $this.HttpResponse.Close()
            }
            catch {
                # Ignore close errors
            }
            $Global:responseClosed = $true
            
            # Clean up cancellation token if available
            if ("CancellationManager" -as [type]) {
                try {
                    [CancellationManager]::RemoveRequest($this.RequestId)
                }
                catch {
                    # Ignore cleanup errors
                }
            }
        }
    }

    [void] RespondAsync() {
        $ResponseBuffer = @()

        if ($Global:responseClosed) {
            Write-Host "Response is already closed."
            return
        }

        if ([string]::IsNullOrEmpty($this.ContentType)) {
            switch ($this.ResponseType) {
                "json" {
                    $this.ContentType = "application/json"
                }
                "html" {
                    $this.ContentType = "text/html"
                }
                "binary" {
                    $this.ContentType = "application/octet-stream"
                }
                Default {}
            }
        }

        if ($this.ContentType) {
            $this.HttpResponse.Headers.Add("Content-Type", $this.ContentType)
        }

        try {
            $cancellationToken = [CancellationManager]::GetToken($this.RequestId)
            
            if ($this.ResponseBytes -and $this.ResponseBytes.Length -gt 0) {
                $ResponseBuffer = $this.ResponseBytes
                $this.SendResponseBufferAsync($ResponseBuffer, $cancellationToken)
            } 
            elseif ($this.ResponseString -and $this.ResponseString.Length -gt 0) {
                $ResponseBuffer = [System.Text.Encoding]::UTF8.GetBytes($this.ResponseString)
                $this.SendResponseBufferAsync($ResponseBuffer, $cancellationToken)
            } 
            elseif ($this.FilePath -and (Test-Path -LiteralPath $this.FilePath)) {
                Write-Host "Sending file: $($this.FilePath)"
                $this.SendFileAsync($this.FilePath, $cancellationToken)
            } 
            else {
                Write-Host "No valid response content found. FilePath: $($this.FilePath)"
                $this.HttpResponse.StatusCode = 404
                $this.HttpResponse.Close()
                $Global:responseClosed = $true
                [CancellationManager]::RemoveRequest($this.RequestId)
            }
        } 
        catch {
            Write-Host "Error in RespondAsync: $_"
            try {
                $this.HttpResponse.StatusCode = 500
                $this.HttpResponse.Close()
            } 
            catch {
                # Ignore errors during cleanup
            }
            $Global:responseClosed = $true
            [CancellationManager]::RemoveRequest($this.RequestId)
        }
    }

    [void] SendResponseBufferAsync([byte[]]$buffer, [System.Threading.CancellationToken]$cancellationToken) {
        $this.HttpResponse.ContentLength64 = $buffer.Length
        
        try {
            # Store 'this' in a local variable to prevent binding issues in the callback
            $localResponse = $this.HttpResponse
            $localRequestId = $this.RequestId
            
            # Create a task to write the buffer to the output stream
            $writeTask = $this.HttpResponse.OutputStream.WriteAsync($buffer, 0, $buffer.Length, $cancellationToken)
            
            # Be explicit about the delegate type to avoid ambiguous overload
            [Action[System.Threading.Tasks.Task]]$continuation = {
                param($task)
                
                try {
                    # Check if task was successful
                    if ($task.IsCompleted -and -not $task.IsFaulted) {
                        $localResponse.OutputStream.Close()
                    }
                }
                catch {
                    Write-Host "Error during response completion: $_"
                }
                finally {
                    $localResponse.Close()
                    $Global:responseClosed = $true
                    [CancellationManager]::RemoveRequest($localRequestId)
                }
            }
            
            # Use explicit continuation
            $writeTask.ContinueWith($continuation)
        }
        catch [System.OperationCanceledException] {
            Write-Host "Request was canceled."
            try {
                $this.HttpResponse.Abort()
            }
            catch {
                # Ignore errors during cleanup after cancellation
            }
            $Global:responseClosed = $true
            [CancellationManager]::RemoveRequest($this.RequestId)
        }
        catch {
            Write-Host "Error sending response buffer: $_"
            try {
                $this.HttpResponse.StatusCode = 500
                $this.HttpResponse.Close()
            }
            catch {
                # Ignore errors during cleanup
            }
            $Global:responseClosed = $true
            [CancellationManager]::RemoveRequest($this.RequestId)
        }
    }

    [void] SendFileAsync([string]$filePath, [System.Threading.CancellationToken]$cancellationToken) {
        try {
            $fileInfo = [System.IO.FileInfo]::new($filePath)
            $this.HttpResponse.ContentLength64 = $fileInfo.Length
            
            # Use FileStream with buffer for more efficient file transfer
            $bufferSize = 81920  # Use an optimal buffer size (80KB)
            $fileStream = [System.IO.File]::OpenRead($filePath)
            $buffer = New-Object byte[] $bufferSize
            
            # Store this reference for callback
            $localResponse = $this.HttpResponse
            $localRequestId = $this.RequestId
            
            # Start the streaming process
            $this.StreamCopyAsync($fileStream, $localResponse.OutputStream, $buffer, $cancellationToken, $localResponse, $localRequestId)
        }
        catch [System.OperationCanceledException] {
            Write-Host "File sending was canceled."
            try {
                $this.HttpResponse.Abort()
            }
            catch {
                # Ignore errors during cleanup after cancellation
            }
            $Global:responseClosed = $true
            [CancellationManager]::RemoveRequest($this.RequestId)
        }
        catch {
            Write-Host "Error sending file: $_"
            try {
                $this.HttpResponse.StatusCode = 500
                $this.HttpResponse.Close()
            }
            catch {
                # Ignore errors during cleanup
            }
            $Global:responseClosed = $true
            [CancellationManager]::RemoveRequest($this.RequestId)
        }
    }

    [void] StreamCopyAsync($source, $destination, [byte[]]$buffer, [System.Threading.CancellationToken]$cancellationToken, $response, $requestId) {
        try {
            # Get a reference to the current instance
            $instance = $this
            
            # Create a simple state object to pass to continuations
            $state = @{
                Source = $source
                Destination = $destination
                Buffer = $buffer
                CancellationToken = $cancellationToken
                Response = $response
                RequestId = $requestId
                Instance = $instance
            }
            
            # Start reading from the source
            $readTask = $source.ReadAsync($buffer, 0, $buffer.Length, $cancellationToken)
            
            # Be explicit about the delegate type for the outer continuation
            [Action[System.Threading.Tasks.Task[int]]]$readContinuation = {
                param($task)
                
                $source = $state.Source
                $destination = $state.Destination
                $buffer = $state.Buffer
                $cancellationToken = $state.CancellationToken
                $response = $state.Response
                $requestId = $state.RequestId
                $instance = $state.Instance
                
                try {
                    if ($task.IsCompleted -and -not $task.IsFaulted -and $task.Result -gt 0) {
                        # Check client connection
                        $clientConnected = $true
                        try {
                            $clientConnected = -not $response.OutputStream.Closed
                        }
                        catch {
                            $clientConnected = $false
                        }
                        
                        if (-not $clientConnected) {
                            [CancellationManager]::CancelRequest($requestId)
                            throw [System.OperationCanceledException]::new("Client disconnected")
                        }
                        
                        # Write the buffer
                        $writeTask = $destination.WriteAsync($buffer, 0, $task.Result, $cancellationToken)
                        
                        # Be explicit about the delegate type for the inner continuation
                        [Action[System.Threading.Tasks.Task]]$writeContinuation = {
                            param($innerTask)
                            
                            if ($innerTask.IsCompleted -and -not $innerTask.IsFaulted) {
                                try {
                                    $instance.StreamCopyAsync(
                                        $source, 
                                        $destination, 
                                        $buffer, 
                                        $cancellationToken, 
                                        $response, 
                                        $requestId)
                                }
                                catch {
                                    Write-Host "Error continuing async stream: $_"
                                }
                            }
                            else {
                                # Handle write failure
                                [CancellationManager]::CancelRequest($requestId)
                                try {
                                    $source.Close()
                                    $destination.Close()
                                    $response.Close()
                                }
                                catch {
                                    # Ignore errors during cleanup
                                }
                                $Global:responseClosed = $true
                                [CancellationManager]::RemoveRequest($requestId)
                            }
                        }
                        
                        # Use explicit continuation
                        $writeTask.ContinueWith($writeContinuation)
                    }
                    else {
                        # End of stream or error
                        try {
                            $source.Close()
                            $destination.Close()
                            $response.Close()
                        }
                        catch {
                            # Ignore errors during cleanup
                        }
                        $Global:responseClosed = $true
                        [CancellationManager]::RemoveRequest($requestId)
                    }
                }
                catch [System.OperationCanceledException] {
                    Write-Host "Stream operation was canceled."
                    try {
                        $source.Close()
                        $destination.Close()
                        $response.Abort()
                    }
                    catch {
                        # Ignore errors during cleanup
                    }
                    $Global:responseClosed = $true
                    [CancellationManager]::RemoveRequest($requestId)
                }
                catch {
                    Write-Host "Error during stream copy: $_"
                    try {
                        $source.Close()
                        $destination.Close()
                        $response.Close()
                    }
                    catch {
                        # Ignore errors during cleanup
                    }
                    $Global:responseClosed = $true
                    [CancellationManager]::RemoveRequest($requestId)
                }
            }
            
            # Use explicit continuation
            $readTask.ContinueWith($readContinuation)
        }
        catch {
            Write-Host "Error starting async read: $_"
            try {
                $source.Close()
                $destination.Close()
                $response.Close()
            }
            catch {
                # Ignore errors during cleanup
            }
            $Global:responseClosed = $true
            [CancellationManager]::RemoveRequest($requestId)
        }
    }
}