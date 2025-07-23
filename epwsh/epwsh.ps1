function es {
    param(
        [Parameter(Mandatory=$true, Position=0, ValueFromRemainingArguments=$true)]
        [string[]]$Query
    )

    # Path to Everything64.dll
    $scriptDir = $PSScriptRoot
    if (-not $scriptDir) {
        $scriptDir = Split-Path $PSCommandPath
    }
    $everythingDllPath = Join-Path $scriptDir "Everything-SDK\dll\Everything64.dll"
    $escapedDllPath = $everythingDllPath -replace '\\', '\\\\'

    if (-not ([System.Management.Automation.PSTypeName]'Everything').Type) {
        $source = @"
using System;
using System.Runtime.InteropServices;

public class Everything
{
    [DllImport("$escapedDllPath", CharSet = CharSet.Unicode)]
    public static extern void Everything_SetSearchW(string search);

    [DllImport("$escapedDllPath")]
    public static extern void Everything_QueryW(bool bWait);

    [DllImport("$escapedDllPath")]
    public static extern int Everything_GetNumResults();

    [DllImport("$escapedDllPath", CharSet = CharSet.Unicode)]
    public static extern int Everything_GetResultFullPathNameW(int nIndex, System.Text.StringBuilder lpString, int nMaxCount);
}
"@
        Add-Type -TypeDefinition $source -Language CSharp
    }

    $queryStr = $Query -join ' '
    [Everything]::Everything_SetSearchW($queryStr)
    [Everything]::Everything_QueryW($true)
    $numResults = [Everything]::Everything_GetNumResults()

    Write-Host "Found $numResults results:"
    for ($i = 0; $i -lt $numResults; $i++) {
        $sb = New-Object System.Text.StringBuilder 260
        $null = [Everything]::Everything_GetResultFullPathNameW($i, $sb, $sb.Capacity)
        $result = $sb.ToString()
        if ($result -and $result -match '^(?:[A-Z]:\\|\\\\)') {
            Write-Host $result
        }
    }
}