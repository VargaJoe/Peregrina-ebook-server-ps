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
            # Set responseClosed flag immediately to prevent other handlers from processing
            $Global:responseClosed = $true
            $this.RespondAsync()
            return
        }

        # Fallback to synchronous response - set flag here for sync mode
        $Global:responseClosed = $true
        $ResponseBuffer = @()

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
                Write-Host "Sending ResponseBytes async: $($this.ResponseBytes.Length) bytes"
                $this.SendResponseBufferAsync($ResponseBuffer, $cancellationToken)
            } 
            elseif ($this.ResponseString -and $this.ResponseString.Length -gt 0) {
                $ResponseBuffer = [System.Text.Encoding]::UTF8.GetBytes($this.ResponseString)
                Write-Host "Sending ResponseString async: $($this.ResponseString.Length) chars -> $($ResponseBuffer.Length) bytes"
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
        Write-Host "SendResponseBufferAsync: Starting to send $($buffer.Length) bytes"
        $this.HttpResponse.ContentLength64 = $buffer.Length
        
        try {
            Write-Host "SendResponseBufferAsync: Creating WriteAsync task"
            # Create a task to write the buffer to the output stream
            $writeTask = $this.HttpResponse.OutputStream.WriteAsync($buffer, 0, $buffer.Length, $cancellationToken)
            
            Write-Host "SendResponseBufferAsync: Waiting for task completion"
            # Instead of using continuation, wait for the task to complete
            # This is more reliable in PowerShell context
            $writeTask.GetAwaiter().GetResult()
            
            Write-Host "SendResponseBufferAsync: Write completed successfully, closing streams"
            $this.HttpResponse.OutputStream.Close()
            $this.HttpResponse.Close()
            
            Write-Host "SendResponseBufferAsync: Setting responseClosed flag and cleaning up"
            $Global:responseClosed = $true
            [CancellationManager]::RemoveRequest($this.RequestId)
            
            Write-Host "SendResponseBufferAsync: Response completed successfully"
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
            Write-Host "DEBUG: Starting StreamCopyAsync for request $requestId"
            
            # Use a simple loop with synchronous waits instead of async continuations
            # This avoids PowerShell async continuation issues
            $totalBytesCopied = 0
            
            while ($true) {
                try {
                    # Check if cancellation was requested
                    if ($cancellationToken.IsCancellationRequested) {
                        Write-Host "DEBUG: StreamCopyAsync cancellation requested for request $requestId"
                        break
                    }
                    
                    # Check client connection
                    $clientConnected = $true
                    try {
                        $clientConnected = -not $response.OutputStream.Closed
                    }
                    catch {
                        $clientConnected = $false
                    }
                    
                    if (-not $clientConnected) {
                        Write-Host "DEBUG: Client disconnected during StreamCopyAsync for request $requestId"
                        [CancellationManager]::CancelRequest($requestId)
                        break
                    }
                    
                    # Read from source
                    $readTask = $source.ReadAsync($buffer, 0, $buffer.Length, $cancellationToken)
                    $bytesRead = $readTask.GetAwaiter().GetResult()
                    
                    Write-Host "DEBUG: StreamCopyAsync read $bytesRead bytes for request $requestId"
                    
                    if ($bytesRead -le 0) {
                        Write-Host "DEBUG: StreamCopyAsync reached end of stream for request $requestId (total: $totalBytesCopied bytes)"
                        break
                    }
                    
                    # Write to destination
                    $writeTask = $destination.WriteAsync($buffer, 0, $bytesRead, $cancellationToken)
                    $writeTask.GetAwaiter().GetResult()
                    
                    $totalBytesCopied += $bytesRead
                    Write-Host "DEBUG: StreamCopyAsync wrote $bytesRead bytes for request $requestId (total: $totalBytesCopied)"
                    
                    # Flush the output to ensure data is sent
                    try {
                        $destination.Flush()
                    }
                    catch {
                        Write-Host "DEBUG: Error flushing destination stream: $_"
                    }
                }
                catch [System.OperationCanceledException] {
                    Write-Host "DEBUG: StreamCopyAsync operation was canceled for request $requestId"
                    break
                }
                catch {
                    Write-Host "DEBUG: Error during StreamCopyAsync loop for request $requestId : $_"
                    break
                }
            }
            
            Write-Host "DEBUG: StreamCopyAsync completed for request $requestId, copied $totalBytesCopied bytes"
            
            # Close streams and clean up
            try {
                $source.Close()
                $destination.Close()
                $response.Close()
                Write-Host "DEBUG: StreamCopyAsync streams closed for request $requestId"
            }
            catch {
                Write-Host "DEBUG: Error closing streams in StreamCopyAsync for request $requestId : $_"
            }
            
            $Global:responseClosed = $true
            [CancellationManager]::RemoveRequest($requestId)
            Write-Host "DEBUG: StreamCopyAsync cleanup completed for request $requestId"
        }
        catch [System.OperationCanceledException] {
            Write-Host "StreamCopyAsync was canceled for request $requestId"
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
            Write-Host "Error in StreamCopyAsync for request $requestId : $_"
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