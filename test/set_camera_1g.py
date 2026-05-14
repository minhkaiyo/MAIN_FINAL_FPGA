import vmbpy
import time
import sys

def main():
    print("--- GigE Camera 1Gbps Configuration Tool ---")
    with vmbpy.VmbSystem.get_instance() as vmb:
        cams = vmb.get_all_cameras()
        if not cams:
            print("[ERROR] No camera found!")
            return
        
        cam = cams[0]
        print(f"[INFO] Connecting to: {cam.get_id()}")
        
        with cam:
            # 1. Check current settings
            try:
                link_speed = cam.get_feature_by_name('DeviceLinkSpeed').get()
                print(f"[READ] Physical Link Speed: {link_speed / 1e6:.1f} Mbps")
            except Exception as e:
                print(f"[WARN] Could not read DeviceLinkSpeed: {e}")

            try:
                throughput = cam.get_feature_by_name('StreamBytesPerSecond').get()
                print(f"[READ] Current Throughput Limit: {throughput / 1e6:.1f} MB/s")
            except Exception as e:
                print(f"[WARN] Could not read StreamBytesPerSecond: {e}")

            # 2. Apply 1Gbps settings
            print("[ACTION] Setting throughput to 115 MB/s (approx 1 Gbps)...")
            try:
                # Set to 115,000,000 bytes/sec
                cam.get_feature_by_name('StreamBytesPerSecond').set(115000000)
                new_val = cam.get_feature_by_name('StreamBytesPerSecond').get()
                print(f"[SUCCESS] New Throughput Limit: {new_val / 1e6:.1f} MB/s")
            except Exception as e:
                print(f"[ERROR] Failed to set StreamBytesPerSecond: {e}")

            # 3. Adjust Packet Size (Optimize for 1Gbps)
            print("[ACTION] Adjusting Packet Size...")
            try:
                cam.get_feature_by_name('GVSPAdjustPacketSize').run()
                while not cam.get_feature_by_name('GVSPAdjustPacketSize').is_done():
                    time.sleep(0.1)
                pkt_size = cam.get_feature_by_name('GevSCPSPacketSize').get()
                print(f"[SUCCESS] Optimized Packet Size: {pkt_size}")
            except Exception as e:
                print(f"[ERROR] Failed to adjust packet size: {e}")

            # 4. Check for Frame Rate
            try:
                fps = cam.get_feature_by_name('AcquisitionFrameRateAbs').get()
                print(f"[READ] Current FPS: {fps:.2f}")
            except:
                try:
                    fps = cam.get_feature_by_name('AcquisitionFrameRate').get()
                    print(f"[READ] Current FPS: {fps:.2f}")
                except:
                    pass

    print("--- Configuration Complete ---")

if __name__ == "__main__":
    main()
