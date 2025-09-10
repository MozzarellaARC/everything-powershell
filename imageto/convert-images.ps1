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

		# Optional starting directory (defaults to current directory)
		[Parameter(Position=1)]
		[string]$Path = '.',

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

	# Resolve and validate path
	try { $resolvedPath = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).ProviderPath } catch { Write-Error "Path not found: $Path"; return }

	# NOTE: -Include without -Recurse can silently return nothing unless the -Path has a wildcard.
	# To avoid that pitfall we enumerate then filter by extension.
	$files = Get-ChildItem -LiteralPath $resolvedPath -File -Recurse:$Recurse -ErrorAction SilentlyContinue |
		Where-Object { $_.Extension -match '\.(jpg|jpeg|png|webp|gif|bmp|tif|tiff|avif|heic)$' }
	if (-not $files) { Write-Warning 'No images found.'; return }

	$magick = Get-Command magick -ErrorAction SilentlyContinue
	$useMagick = $magick -ne $null
	$basicDecodable = 'jpg','jpeg','png','gif','bmp','tif','tiff'
	if (-not $useMagick) {
		# If target itself is an advanced format we can't proceed
		if ($Format -notin $basicDecodable) {
			Write-Warning "Target format '$Format' requires ImageMagick (magick.exe). Install ImageMagick for full support."
			return
		}
		# Filter out source images we can't decode with System.Drawing
		$unsupportedSources = $files | Where-Object { ($_.Extension.TrimStart('.').ToLower()) -notin $basicDecodable }
		if ($unsupportedSources) {
			$preview = ($unsupportedSources | Select-Object -First 5 -ExpandProperty Name) -join ', '
			Write-Warning "Skipping unsupported source formats without ImageMagick: $preview" 
			$files = $files | Where-Object { ($_.Extension.TrimStart('.').ToLower()) -in $basicDecodable }
			if (-not $files) { Write-Warning 'No convertible images with current fallback.'; return }
		}
		# Load System.Drawing for basic formats
		Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue | Out-Null
	}

	$countTotal = 0
	$countConverted = 0
	$countSkipped = 0
	$countUnsupported = 0
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

	Write-Host "Total: $countTotal | Converted: $countConverted | Skipped (already target): $countSkipped | Errors: $errors" -ForegroundColor Cyan
	if (-not $useMagick) { Write-Host 'Tip: Install ImageMagick (winget install ImageMagick.ImageMagick) for webp/avif/heic support.' -ForegroundColor DarkCyan }
}

# If script is executed directly (not dot-sourced) allow quick one-off usage: .\convert-images.ps1 png
if ($MyInvocation.InvocationName -ne '.') {
	if ($args.Count -gt 0) {
		imageto @args
	}
}

