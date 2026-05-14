# stream_gige_camera.py
# GigE Camera -> FPGA via UDP (RGB332 color mode)
# Compatible with sdram_ethernet_stream_v4.v VGA pipeline

import vimba
import socket
import struct
import time
import cv2
import numpy as np

# --- CONFIG ---
FPGA_IP = "255.255.255.255"
FPGA_PORT = 1234
WIDTH = 640
HEIGHT = 480

def rgb_to_rgb332(img_bgr):
    """Convert BGR image to RGB332 format (1 byte per pixel)
    R[7:5] = 3 bit Red, G[4:2] = 3 bit Green, B[1:0] = 2 bit Blue"""
    b = img_bgr[:, :, 0].astype(np.uint16)
    g = img_bgr[:, :, 1].astype(np.uint16)
    r = img_bgr[:, :, 2].astype(np.uint16)
    # Quantize: R->3bit, G->3bit, B->2bit
    rgb332 = ((r >> 5) << 5) | ((g >> 5) << 2) | (b >> 6)
    return rgb332.astype(np.uint8)

def main():
    print("=== GigE Camera -> FPGA (RGB332 Color Mode) ===")
    
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    try:
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, 2 * 1024 * 1024)
    except:
        pass
    
    with vimba.Vimba.get_instance() as vmb:
        time.sleep(0.5)
        cams = vmb.get_all_cameras()
        if not cams:
            print("[ERROR] No camera found!")
            return
        
        cam = cams[0]
        print(f"[INFO] Found Camera: {cam.get_id()}")
        
        with cam:
            print("[OK] Camera opened.")
            
            # Try to set color mode for RGB332 output
            try:
                # Try BayerRG8 first (most Mako cameras support this)
                cam.get_feature_by_name('PixelFormat').set('BayerRG8')
                color_mode = 'BayerRG8'
            except:
                try:
                    cam.get_feature_by_name('PixelFormat').set('Mono8')
                    color_mode = 'Mono8'
                except:
                    color_mode = 'Unknown'
            
            try:
                cam.get_feature_by_name('Width').set(WIDTH)
                cam.get_feature_by_name('Height').set(HEIGHT)
            except Exception as e:
                print(f"[WARN] Resolution: {e}")
            
            try:
                cam.get_feature_by_name('StreamBytesPerSecond').set(115000000)
            except:
                pass
                
            print(f"[OK] Config: {WIDTH}x{HEIGHT}, {color_mode}")
            print(f"[STREAMING] -> {FPGA_IP}:{FPGA_PORT}")
            
            frame_count = 0
            t0 = time.time()
            header_struct = struct.Struct('>H')

            try:
                while True:
                    frame = cam.get_frame(timeout_ms=2000)
                    
                    h = frame.get_height()
                    w = frame.get_width()
                    raw = np.ndarray(buffer=frame.get_buffer(),
                                    dtype=np.uint8, shape=(h, w))
                    
                    if color_mode == 'BayerRG8':
                        # Debayer to BGR
                        bgr = cv2.cvtColor(raw, cv2.COLOR_BayerRG2BGR)
                        # Convert to RGB332
                        img332 = rgb_to_rgb332(bgr)
                    else:
                        # Mono8: map grayscale to RGB332
                        # R=gray[7:5], G=gray[7:5], B=gray[7:6]
                        img332 = ((raw >> 5) << 5) | ((raw >> 5) << 2) | (raw >> 6)
                    
                    # Send each row via UDP
                    for y in range(HEIGHT):
                        payload = header_struct.pack(y) + img332[y].tobytes()
                        sock.sendto(payload, (FPGA_IP, FPGA_PORT))
                    
                    frame_count += 1
                    
                    now = time.time()
                    if now - t0 >= 2.0:
                        fps = frame_count / (now - t0)
                        print(f"  Speed: {fps:.1f} FPS ({color_mode})")
                        frame_count = 0
                        t0 = now
                        
            except KeyboardInterrupt:
                print("\n[STOP] User stopped.")
            except Exception as e:
                print(f"\n[ERROR] {e}")
            finally:
                print("[INFO] Done.")

    print("=== Exit ===")

if __name__ == "__main__":
    main()
