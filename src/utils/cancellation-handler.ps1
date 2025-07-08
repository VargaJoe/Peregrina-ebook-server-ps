# Load necessary assemblies
Add-Type -AssemblyName System.Collections

# Define a simple implementation of CancellationManager
$code = @"
using System;
using System.Collections.Concurrent;
using System.Threading;
using System.Threading.Tasks;

public static class CancellationManager
{
    private static ConcurrentDictionary<string, CancellationTokenSource> requestTokens = 
        new ConcurrentDictionary<string, CancellationTokenSource>();

    public static void RegisterRequest(string requestId)
    {
        var tokenSource = new CancellationTokenSource();
        requestTokens[requestId] = tokenSource;
    }

    public static CancellationToken GetToken(string requestId)
    {
        if (requestTokens.ContainsKey(requestId))
        {
            return requestTokens[requestId].Token;
        }
        return CancellationToken.None;
    }

    public static void CancelRequest(string requestId)
    {
        if (requestTokens.ContainsKey(requestId))
        {
            try
            {
                requestTokens[requestId].Cancel();
            }
            catch
            {
                // Ignore exceptions during cancellation
            }
        }
    }

    public static void RemoveRequest(string requestId)
    {
        CancellationTokenSource tokenSource;
        if (requestTokens.TryRemove(requestId, out tokenSource))
        {
            try
            {
                tokenSource.Dispose();
            }
            catch
            {
                // Ignore exceptions during disposal
            }
        }
    }

    public static void CleanupOldRequests()
    {
        foreach (var key in requestTokens.Keys)
        {
            var tokenSource = requestTokens[key];
            if (tokenSource.IsCancellationRequested)
            {
                CancellationTokenSource temp;
                requestTokens.TryRemove(key, out temp);
                try { temp.Dispose(); } catch {}
            }
        }
    }
    
    public static int ActiveRequestCount()
    {
        return requestTokens.Count;
    }
}

public static class AsyncHelper
{
    // Simple continuation with basic handling
    public static void ContinueWith(this Task task, Action<Task> action)
    {
        task.ContinueWith(action);
    }

    public static void ContinueWith<T>(this Task<T> task, Action<Task<T>> action)
    {
        task.ContinueWith(action);
    }

    // Continuation with ConfigureAwait - useful to avoid SyncContext issues
    public static void ContinueWithNoContext(this Task task, Action<Task> action)
    {
        task.ConfigureAwait(false).GetAwaiter().OnCompleted(() => 
        {
            try 
            {
                action(task);
            }
            catch (Exception ex)
            {
                Console.WriteLine("Exception in continuation: " + ex.Message);
            }
        });
    }
    
    public static void ContinueWithNoContext<T>(this Task<T> task, Action<Task<T>> action)
    {
        task.ConfigureAwait(false).GetAwaiter().OnCompleted(() => 
        {
            try 
            {
                action(task);
            }
            catch (Exception ex)
            {
                Console.WriteLine("Exception in continuation: " + ex.Message);
            }
        });
    }
    
    // Legacy methods for backward compatibility
    public static void ContinueWithAction(this Task task, Action<Task> action)
    {
        ContinueWithNoContext(task, action);
    }
    
    public static void ContinueWithAction<T>(this Task<T> task, Action<Task<T>> action)
    {
        ContinueWithNoContext(task, action);
    }
    
    // State capture methods (simplest implementation)
    public static void ContinueWith<TState>(this Task task, TState state, Action<Task, TState> action)
    {
        task.ContinueWith(t => action(t, state));
    }
    
    public static void ContinueWith<T, TState>(this Task<T> task, TState state, Action<Task<T>, TState> action)
    {
        task.ContinueWith(t => action(t, state));
    }
    
    // Safe state capture with exception handling
    public static void ContinueWithSafe<TState>(this Task task, TState state, Action<Task, TState> action)
    {
        task.ContinueWith(t => 
        {
            try 
            {
                action(t, state);
            }
            catch (Exception ex)
            {
                Console.WriteLine("Exception in state continuation: " + ex.Message);
            }
        });
    }
    
    public static void ContinueWithSafe<T, TState>(this Task<T> task, TState state, Action<Task<T>, TState> action)
    {
        task.ContinueWith(t => 
        {
            try 
            {
                action(t, state);
            }
            catch (Exception ex)
            {
                Console.WriteLine("Exception in state continuation: " + ex.Message);
            }
        });
    }
    
    // Safe state capture with ConfigureAwait to avoid context issues
    public static void ContinueWithSafeClosure<TState>(this Task task, TState state, Action<Task, TState> action)
    {
        task.ConfigureAwait(false).GetAwaiter().OnCompleted(() => 
        {
            try 
            {
                action(task, state);
            }
            catch (Exception ex)
            {
                Console.WriteLine("Exception in safe closure: " + ex.Message);
            }
        });
    }
    
    public static void ContinueWithSafeClosure<T, TState>(this Task<T> task, TState state, Action<Task<T>, TState> action)
    {
        task.ConfigureAwait(false).GetAwaiter().OnCompleted(() => 
        {
            try 
            {
                action(task, state);
            }
            catch (Exception ex)
            {
                Console.WriteLine("Exception in safe closure: " + ex.Message);
            }
        });
    }
}
"@

# Try to compile and load the type
try {
    Add-Type -TypeDefinition $code -Language CSharp -ErrorAction Stop
}
catch {
    Write-Host "Error loading CancellationManager: $_"
}

# Function to check if client is still connected
function Test-ClientConnected {
    param (
        [Parameter(Mandatory = $true)]
        [System.Net.HttpListenerResponse] $Response
    )
    
    try {
        # Try to check if client is still connected
        $canWrite = -not $Response.OutputStream.Closed
        return $canWrite
    }
    catch {
        return $false
    }
}