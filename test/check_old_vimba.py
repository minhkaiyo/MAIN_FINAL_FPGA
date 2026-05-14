import vimba
try:
    with vimba.Vimba.get_instance() as v:
        cams = v.get_all_cameras()
        print(f"Old Vimba Cameras found: {len(cams)}")
        for i, cam in enumerate(cams):
            print(f"Cam {i}: {cam.get_id()}")
except Exception as e:
    print(f"Error: {e}")
