import vimba

def set_persistent_ip():
    with vimba.Vimba.get_instance() as v:
        cams = v.get_all_cameras()
        if not cams:
            print("No camera found!")
            return
            
        cam = cams[0]
        # Mở camera bình thường (Vimba tự động Exclusive)
        with cam:
            print(f"Configuring Camera: {cam.get_id()}")
            
            # Tính toán IP 192.168.1.164
            ip_int = (192 << 24) | (168 << 16) | (1 << 8) | 164
            mask_int = (255 << 24) | (255 << 16) | (255 << 8) | 0
            
            try:
                # Mako camera dùng Enum: 'Persistent', 'DHCP', 'LLA'
                cam.get_feature_by_name('GevIPConfigurationMode').set('Persistent')
                
                # Set IP và Mask
                cam.get_feature_by_name('GevPersistentIPAddress').set(ip_int)
                cam.get_feature_by_name('GevPersistentSubnetMask').set(mask_int)
                
                print("SUCCESS: Camera is now permanently locked to 192.168.1.164")
            except Exception as e:
                print(f"Error: {e}")

if __name__ == '__main__':
    set_persistent_ip()
