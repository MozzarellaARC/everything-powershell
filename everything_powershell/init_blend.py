import bpy, os
filepath = os.path.join(os.getcwd(), "my_scene.blend")
bpy.ops.wm.save_as_mainfile(filepath=filepath)
print(f"Saved {filepath}")
# no sys.exit() → Blender will stay open
