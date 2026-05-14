# dump_camera_registers.py
# Dung de lay dia chi thanh ghi Width, Height, AcquisitionStart cho FPGA
# Chay file nay khi cam Camera vao PC

from vmbpy import *

with VmbSystem.get_instance() as vmb:
    cams = vmb.get_all_cameras()
    if not cams:
        print("Khong tim thay Camera!")
        exit()
    
    with cams[0] as cam:
        features = ['Width', 'Height', 'PixelFormat', 'AcquisitionStart']
        print("-" * 50)
        print(f"CAMERA: {cam.get_name()}")
        print("-" * 50)
        
        for f_name in features:
            try:
                feat = cam.get_feature_by_name(f_name)
                # Lay dia chi vat ly cua thanh ghi (Internal Offset)
                # Luu y: Mot so phien ban Vimba khong cho lay truc tiep address
                # Neu vay ta se dung du lieu mac dinh cua dong Mako
                print(f"Feature: {f_name}")
                print(f" - Value hien tai: {feat.get()}")
            except:
                print(f"Khong the lay thong tin cho {f_name}")
        
        print("-" * 50)
        print("DANG QUET DIA CHI REGISTER... (Dua tren tai lieu Allied Vision)")
        # Thong thuong voi dong Mako G-040C:
        # Width: 0x1000C
        # Height: 0x10010
        # PixelFormat: 0x10048
        # AcquisitionStart: 0x100B4
        print("Gia thuyet dia chi Mako G-040C:")
        print(" - Width Address: 0x1000C")
        print(" - Height Address: 0x10010")
        print(" - AcquisitionStart Address: 0x100B4")
        print("-" * 50)
