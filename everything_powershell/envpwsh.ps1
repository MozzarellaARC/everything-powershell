# Retrieve the current user's Path environment variable

function Get-EnvironmentVariables {
    # Get the Path environment variable for the current user
    $path = [System.Environment]::GetEnvironmentVariable("Path", "User")

    # Check if the Path variable exists
    if ($null -eq $path) {
        Write-Output "No Path variable found for the current user."
    } else {
        # Split the Path into individual directories (using platform-appropriate delimiter)
        $delimiter = if ($env:OS -like "Windows*") { ";" } else { ":" }
        $pathArray = $path -split $delimiter

        # Display in a readable format with numbering
        Write-Output "Current User's Path Environment Variable:"
        Write-Output "----------------------------------------"
        $pathArray | ForEach-Object { $i = 1 } { Write-Output "$i. $_"; $i++ }
    }
}

Set-Alias -Name pow -Value Get-EnvironmentVariables