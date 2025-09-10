<#+
 .SYNOPSIS
  Bulk-convert all images in the current directory to a target format.

 .USAGE
  # Load (dot-source) this script first if not in your profile:
  # . .\convert-images.ps1
  # Then run:
  # imageto jpeg
  # imageto png
  # imageto webp

 .NOTES
  If ImageMagick (magick.exe) is available in PATH it will be used (supports webp/avif/heic etc).
  Without ImageMagick, a fallback .NET conversion is used (only: jpg/jpeg, png, bmp, gif, tif/tiff).
  Existing target files are not overwritten unless -Force is specified.
#>

function imageto {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory, Position=0)]
		[ValidateNotNullOrEmpty()]
		[string]$Format,

		[switch]$Recurse,
		[switch]$Force
	)

	$origFormatInput = $Format
	$Format = $Format.ToLower()
	if ($Format -eq 'jpg') { $Format = 'jpeg' }

	$validTargets = 'jpeg','png','webp','gif','bmp','tiff','tif','avif','heic'
	if ($validTargets -notcontains $Format) {
		Write-Error "Unsupported target format '$origFormatInput'. Supported: $($validTargets -join ', ')"; return
	}

	$searchPatterns = @('*.jpg','*.jpeg','*.png','*.webp','*.gif','*.bmp','*.tif','*.tiff','*.avif','*.heic')
	$gciParams = @{ File = $true; Include = $searchPatterns }
	if ($Recurse) { $gciParams.Recurse = $true }
	$files = Get-ChildItem @gciParams | Where-Object { -not $_.PSIsContainer }
	if (-not $files) { Write-Warning 'No images found.'; return }

	$magick = Get-Command magick -ErrorAction SilentlyContinue
	$useMagick = $magick -ne $null
	if (-not $useMagick) {
		# Determine whether .NET fallback will suffice
		$unsupported = $files | Where-Object { $_.Extension -match '\.(webp|avif|heic)$' }
		if ($unsupported -and ($Format -match 'webp|avif|heic')) {
			Write-Warning 'Advanced formats requested but magick.exe not found. Install ImageMagick for full support.'
			return
		}
		# Load System.Drawing for basic formats
		Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue | Out-Null
	}

	$countTotal = 0
	$countConverted = 0
	$countSkipped = 0
	$errors = 0

	foreach ($file in $files) {
		$countTotal++
		$currentExt = $file.Extension.TrimStart('.')
		if ($currentExt.ToLower() -eq $Format.Trim('.')) {
			$countSkipped++
			continue
		}
		$baseName = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
		$targetExt = if ($Format -in @('tif')) { 'tif' } elseif ($Format -eq 'tiff') { 'tiff' } else { $Format }
		$outPath = Join-Path $file.DirectoryName ("$baseName.$targetExt")

		if ((-not $Force) -and (Test-Path $outPath)) {
			# Find a unique name
			$i = 1
			while (Test-Path (Join-Path $file.DirectoryName ("$baseName-$i.$targetExt"))) { $i++ }
			$outPath = Join-Path $file.DirectoryName ("$baseName-$i.$targetExt")
		}

		try {
			if ($useMagick) {
				& $magick.Source "$($file.FullName)" "$outPath" 2>$null
			} else {
				$img = [System.Drawing.Image]::FromFile($file.FullName)
				$encoderFormat = switch ($Format) {
					'jpeg' { [System.Drawing.Imaging.ImageFormat]::Jpeg }
					'png'  { [System.Drawing.Imaging.ImageFormat]::Png }
					'gif'  { [System.Drawing.Imaging.ImageFormat]::Gif }
					'bmp'  { [System.Drawing.Imaging.ImageFormat]::Bmp }
					'tif'  { [System.Drawing.Imaging.ImageFormat]::Tiff }
					'tiff' { [System.Drawing.Imaging.ImageFormat]::Tiff }
					default { throw "Format '$Format' not supported without ImageMagick." }
				}
				$img.Save($outPath, $encoderFormat)
				$img.Dispose()
			}
			if (Test-Path $outPath) {
				$countConverted++
			} else {
				throw 'Conversion produced no file.'
			}
		} catch {
			Write-Warning "Failed to convert '$($file.Name)': $_"
			$errors++
		}
	}

	Write-Host "Total: $countTotal | Converted: $countConverted | Skipped: $countSkipped | Errors: $errors" -ForegroundColor Cyan
}

# If script is executed directly (not dot-sourced) allow quick one-off usage: .\convert-images.ps1 png
if ($MyInvocation.InvocationName -ne '.') {
	if ($args.Count -gt 0) {
		imageto @args
	}
}

