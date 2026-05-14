import vmbpy
try:
    with vmbpy.VmbSystem.get_instance() as vmb:
        cams = vmb.get_all_cameras()
        print(f"Cameras found: {len(cams)}")
        for i, cam in enumerate(cams):
            print(f"Cam {i}: {cam.get_id()} - {cam.get_name()}")
except Exception as e:
    print(f"Error: {e}")
