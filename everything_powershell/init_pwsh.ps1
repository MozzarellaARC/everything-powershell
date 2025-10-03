function Init {
    param (
        [switch]$Blend
    )

    if ($Blend) {
        blender --background --python-expr "import bpy, os; bpy.ops.wm.save_as_mainfile(filepath=os.path.join(os.getcwd(), 'my_scene.blend'))"
        blender my_scene.blend
    }
    else {
        Write-Output "Blender binary not found"
    }
}
