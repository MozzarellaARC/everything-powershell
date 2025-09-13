function Test-FdAvailable { return [bool](Get-Command fd -ErrorAction SilentlyContinue) }

function Invoke-FdSearch {
  param(
    [string]$Pattern,
    [int]$Limit = 200,
    [switch]$Files,
    [switch]$Dirs,
    [string[]]$Extensions,
    [string[]]$Paths
  )
  if (-not (Test-FdAvailable)) { return @() }
  if (-not $Pattern) { $Pattern = '' }
  $args = @('--color','never','--max-results',$Limit)
  if ($Files) { $args += @('-t','f') }
  if ($Dirs) { $args += @('-t','d') }
  foreach ($ext in ($Extensions | Where-Object { $_ })) { $args += @('-e',$ext) }
  if ($Paths -and $Paths.Count -gt 0) {
    foreach ($p in $Paths) { if (Test-Path $p) { $args += '--search-path'; $args += (Resolve-Path $p).Path } }
  }
  $args += $Pattern
  try { fd @args 2>$null } catch { @() }
}


function es {
  <#
  fd-backed filesystem search (replacement for Everything SDK).
  Examples:
    es foo bar            # search pattern "foo bar" (exact literal passed to fd which does fuzzy substring)
    es -ext ps1 -ext psd1 config  # limit to extensions
    es -files readme       # files only
    es -dirs src           # directories only
    es -path C:\Projects -path D:\Work build
  #>
  [CmdletBinding()]
  param(
    [Parameter(Position=0, ValueFromRemainingArguments=$true)] [string[]]$Query,
    [Parameter()] [string[]]$Ext,
    [switch]$Files,
    [switch]$Dirs,
    [Parameter()] [string[]]$Path,
    [int]$Limit = 200
  )

  if ($Files -and $Dirs) { Write-Warning "Cannot specify both -Files and -Dirs; ignoring both."; $Files=$false; $Dirs=$false }
  $pattern = ($Query -join ' ').Trim()

  if (-not (Test-FdAvailable)) {
    Write-Error "'fd' is required but was not found in PATH. Install from https://github.com/sharkdp/fd/releases and try again."; return
  }
  Write-Host "🔍 fd search: '$pattern'" -ForegroundColor Cyan
  $results = Invoke-FdSearch -Pattern $pattern -Limit $Limit -Files:$Files -Dirs:$Dirs -Extensions $Ext -Paths $Path

  if (-not $results -or $results.Count -eq 0) { Write-Host "No results." -ForegroundColor Yellow; return }
  $idx = 0
  foreach ($r in $results) { Write-Host ("[{0}] {1}" -f $idx, $r); $idx++ }
}