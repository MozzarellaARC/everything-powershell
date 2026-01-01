# PlayPwsh.ps1 - Music player using ffplay and fuzzy finder
# Requires: ffmpeg (ffplay), fzf

param(
    [Parameter(Position=0)]
    [string]$Query,
    [string]$MusicFolder = "C:\Users\M\Music",
    [switch]$Recursive,
    [switch]$Shuffle,
    [string]$FileTypes = "*.mp3,*.flac,*.wav,*.m4a,*.ogg,*.wma,*.aac,*.opus,*.mp4,*.mkv,*.avi,*.webm,*.mov",
    [switch]$Help
)

function Show-Help {
    Write-Host "`nPlayPwsh - Music Player with Fuzzy Finder" -ForegroundColor Cyan
    Write-Host "=========================================" -ForegroundColor Cyan
    Write-Host "`nDESCRIPTION:" -ForegroundColor Yellow
    Write-Host "  Play music files using ffplay with fzf fuzzy finder for easy selection."
    Write-Host "`nUSAGE:" -ForegroundColor Yellow
    Write-Host "  .\PlayPwsh.ps1 <query> [options]"
    Write-Host "  play <query> [options]          (using alias)"
    Write-Host "`nPARAMETERS:" -ForegroundColor Yellow
    Write-Host "  <query>" -ForegroundColor Green
    Write-Host "      Search query to filter music files (e.g., 'bohemian rhapsody')"
    Write-Host "      If provided, pre-filters results with fzf"
    Write-Host "`n  -MusicFolder <path>" -ForegroundColor Green
    Write-Host "      Path to your music folder (default: %USERPROFILE%\Music)"
    Write-Host "`n  -Recursive" -ForegroundColor Green
    Write-Host "      Scan subfolders recursively for music files"
    Write-Host "`n  -Shuffle" -ForegroundColor Green
    Write-Host "      Shuffle the file list before displaying"
    Write-Host "`n  -FileTypes <extensions>" -ForegroundColor Green
    Write-Host "      Comma-separated list of file extensions to search for"
    Write-Host "      (default: *.mp3,*.flac,*.wav,*.m4a,*.ogg,*.wma,*.aac,*.opus)"
    Write-Host "`n  -Help" -ForegroundColor Green
    Write-Host "      Display this help message"
    Write-Host "`nEXAMPLES:" -ForegroundColor Yellow
    Write-Host "  .\PlayPwsh.ps1"
    Write-Host "      Browse all music files"
    Write-Host "`n  play 'bohemian rhapsody'"
    Write-Host "      Search for 'bohemian rhapsody' and play (using alias)"
    Write-Host "`n  .\PlayPwsh.ps1 -Recursive -Shuffle"
    Write-Host "      Scan recursively and shuffle the list"
    Write-Host "`n  .\PlayPwsh.ps1 -MusicFolder 'D:\MyMusic' -Recursive"
    Write-Host "      Use custom music folder with recursive scan"
    Write-Host "`n  .\PlayPwsh.ps1 -FileTypes '*.mp3,*.flac'"
    Write-Host "      Only show MP3 and FLAC files"
    Write-Host "`nPLAYBACK CONTROLS:" -ForegroundColor Yellow
    Write-Host "  q     - Quit playback"
    Write-Host "  s     - Toggle pause"
    Write-Host "  ←/→   - Seek backward/forward 10 seconds"
    Write-Host "  ↑/↓   - Seek backward/forward 1 minute"
    Write-Host "`nREQUIREMENTS:" -ForegroundColor Yellow
    Write-Host "  - ffmpeg (ffplay):  winget install ffmpeg"
    Write-Host "  - fzf:              winget install fzf"
    Write-Host ""
}

function Test-Dependencies {
    $missing = @()
    
    if (-not (Get-Command ffplay -ErrorAction SilentlyContinue)) {
        $missing += "ffplay (from ffmpeg)"
    }
    
    if (-not (Get-Command fzf -ErrorAction SilentlyContinue)) {
        $missing += "fzf"
    }
    
    if ($missing.Count -gt 0) {
        Write-Host "Missing dependencies: $($missing -join ', ')" -ForegroundColor Red
        Write-Host "`nInstall instructions:" -ForegroundColor Yellow
        Write-Host "  ffmpeg: winget install ffmpeg or choco install ffmpeg"
        Write-Host "  fzf:    winget install fzf or choco install fzf"
        return $false
    }
    
    return $true
}

function Get-MusicFiles {
    param(
        [string]$Path,
        [string[]]$Extensions,
        [bool]$IsRecursive
    )
    
    if (-not (Test-Path $Path)) {
        Write-Host "Music folder not found: $Path" -ForegroundColor Red
        return @()
    }
    
    $files = @()
    foreach ($ext in $Extensions) {
        if ($IsRecursive) {
            $files += @(Get-ChildItem -Path $Path -Filter $ext -Recurse -File -ErrorAction SilentlyContinue)
        } else {
            $files += @(Get-ChildItem -Path $Path -Filter $ext -File -ErrorAction SilentlyContinue)
        }
    }
    
    return ,@($files)
}

function Play-Music {
    param(
        [string]$FilePath
    )
    
    if (-not (Test-Path $FilePath)) {
        Write-Host "File not found: $FilePath" -ForegroundColor Red
        return
    }
    
    Write-Host "`nNow playing: " -NoNewline -ForegroundColor Green
    Write-Host (Split-Path $FilePath -Leaf) -ForegroundColor Cyan
    Write-Host "Press 'q' to quit, 's' to toggle pause" -ForegroundColor Gray
    
    # ffplay options:
    # -nodisp: no video display window
    # -autoexit: exit when playback finishes
    # -loglevel quiet: reduce console output
    & ffplay -nodisp -autoexit -loglevel quiet $FilePath
}

# Export alias function for 'play' command
function global:Invoke-PlayMusic {
    param(
        [Parameter(Position=0)]
        [string]$Query,
        [switch]$Recursive,
        [switch]$Shuffle
    )
    
    $scriptPath = Join-Path $PSScriptRoot "PlayPwsh.ps1"
    & $scriptPath -Query $Query -Recursive:$Recursive -Shuffle:$Shuffle
}

Set-Alias -Name play -Value Invoke-PlayMusic -Scope Global

# Only run main script if not dot-sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Main script
    if ($Help) {
        Show-Help
        exit 0
    }

    if (-not (Test-Dependencies)) {
        exit 1
    }

# Parse file extensions
$extensions = $FileTypes -split ',' | ForEach-Object { $_.Trim() }

Write-Host "Scanning music folder: $MusicFolder" -ForegroundColor Cyan
$musicFiles = Get-MusicFiles -Path $MusicFolder -Extensions $extensions -IsRecursive $Recursive

if ($musicFiles.Count -eq 0) {
    Write-Host "No music files found in $MusicFolder" -ForegroundColor Yellow
    exit 0
}

Write-Host "Found $($musicFiles.Count) music files" -ForegroundColor Green

# Prepare file list for fzf
$fileList = $musicFiles | ForEach-Object {
    if ($Recursive) {
        # Show relative path for better navigation
        $relativePath = $_.FullName.Replace($MusicFolder, "").TrimStart('\', '/')
        "$relativePath`t$($_.FullName)"
    } else {
        "$($_.Name)`t$($_.FullName)"
    }
}

# Shuffle if requested
if ($Shuffle) {
    $fileList = $fileList | Get-Random -Count $fileList.Count
}

# If query provided, try to auto-play best match
if ($Query) {
    # Filter files by query (case-insensitive)
    $matches = @($fileList | Where-Object { $_ -like "*$Query*" })
    
    if ($matches.Count -eq 0) {
        Write-Host "No files matching '$Query' found" -ForegroundColor Yellow
        exit 0
    }
    
    # Auto-play the first match
    Write-Host "Found $($matches.Count) match(es) for '$Query'" -ForegroundColor Green
    $selected = $matches | Select-Object -First 1
} else {
    # Use fzf to select file(s)
    # --multi: allow multiple selections
    # --preview: show file info
    # --header: display instructions
    $fzfOptions = @(
        '--multi'
        '--reverse'
        '--height=100%'
        '--header=Select music file(s) to play (Tab to select multiple, Enter to confirm)'
        '--preview=echo File: {1}'
        '--preview-window=up:3:wrap'
    )
    
    $selected = $fileList | fzf @fzfOptions
    
    if (-not $selected) {
        Write-Host "No file selected" -ForegroundColor Yellow
        exit 0
    }
}

# Play selected files
$selectedFiles = @()
if ($selected -is [array]) {
    $selectedFiles = $selected
} else {
    $selectedFiles = @($selected)
}

foreach ($item in $selectedFiles) {
    $fullPath = ($item -split "`t")[1]
    Play-Music -FilePath $fullPath
}

Write-Host "`nPlayback complete!" -ForegroundColor Green
}