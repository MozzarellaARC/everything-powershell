function Init {
    param (
        [switch]$Blend,
        [string]$FileName = "my_scene.blend"
    )

    if ($Blend) {
        # Ensure filename ends with .blend
        if (-not $FileName.EndsWith(".blend")) {
            $FileName += ".blend"
        }

        # Current CLI directory (so Quake mode works)
        $cwd = Get-Location
        $blendPath = Join-Path $cwd $FileName

        # Build a Python script dynamically
        $pyScript = @"
import bpy, os
filepath = r"$blendPath"
bpy.ops.wm.save_as_mainfile(filepath=filepath)
print(f"Saved blend to: {filepath}")
"@

        # Save to a temporary script file
        $tempFile = [System.IO.Path]::GetTempFileName() + ".py"
        Set-Content -Path $tempFile -Value $pyScript -Encoding UTF8

        # Launch Blender GUI with the script and keep it open
        Start-Process blender -ArgumentList "--python", "`"$tempFile`""
    }
    else {
        Write-Output "Use -Blend to initialize a new blend file. Example: Init -Blend -FileName MyProject"
    }
}
