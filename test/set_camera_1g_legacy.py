from vimba import *
import time

def main():
    print("--- GigE Camera 1Gbps Configuration (Legacy SDK) ---")
    with Vimba.get_instance() as vimba:
        cams = vimba.get_all_cameras()
        if not cams:
            print("[ERROR] No camera found!")
            return
        
        cam = cams[0]
        print(f"[INFO] Connecting to: {cam.get_id()}")
        
        with cam:
            # 1. Set Throughput
            try:
                # Legacy SDK feature name is usually the same
                feat = cam.get_feature_by_name('StreamBytesPerSecond')
                feat.set(115000000)
                print(f"[SUCCESS] StreamBytesPerSecond set to: {feat.get() / 1e6:.1f} MB/s")
            except Exception as e:
                print(f"[ERROR] StreamBytesPerSecond fail: {e}")

            # 2. Adjust Packet Size
            try:
                adj = cam.get_feature_by_name('GVSPAdjustPacketSize')
                adj.run()
                while not adj.is_done():
                    time.sleep(0.1)
                pkt = cam.get_feature_by_name('GevSCPSPacketSize')
                print(f"[SUCCESS] Packet Size optimized to: {pkt.get()}")
            except Exception as e:
                print(f"[ERROR] Packet Size fail: {e}")

if __name__ == "__main__":
    main()
