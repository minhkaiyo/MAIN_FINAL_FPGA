import numpy as np
import cv2
import socket
import time
import struct
import sys
from vmbpy import VmbSystem, FrameStatus

# --- CẤU HÌNH HỆ THỐNG ---
FPGA_IP   = "255.255.255.255" # IP của FPGA (Cần khớp với config mạng của bạn)
FPGA_PORT = 1234
IMG_W, IMG_H = 320, 240     # Độ phân giải hiển thị trên FPGA
TARGET_FPS   = 60           # Tốc độ mong muốn
MAX_PAYLOAD  = 1400         # Bytes payload UDP (Header 5B + 697 Pixels * 2B)

def rgb888_to_rgb565(img):
    """
    Chuyển numpy array BGR (OpenCV) sang RGB565 uint16.
    RGB565: [R:15-11] [G:10-5] [B:4-0]
    """
    img_rgb = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
    r = (img_rgb[:,:,0] >> 3).astype(np.uint16)
    g = (img_rgb[:,:,1] >> 2).astype(np.uint16)
    b = (img_rgb[:,:,2] >> 3).astype(np.uint16)
    return (r << 11) | (g << 5) | b

def send_frame(sock, addr, rgb565_data):
    """
    Chia frame thành các gói UDP theo giao thức FPGA v2.
    Header (5 Bytes): [0x55, 0xAA] [Offset 23:16] [Offset 15:8] [Offset 7:0]
    """
    flat = rgb565_data.flatten()
    data_bytes = flat.tobytes() # Little-endian bytes
    
    total_pixels = len(flat)
    pixel_offset = 0
    
    # Số pixel tối đa trong 1 packet (trừ header 5 bytes)
    pixels_per_packet = (MAX_PAYLOAD - 5) // 2 
    
    while pixel_offset < total_pixels:
        # Header: Magic(2) + Offset(3)
        # Offset là số thứ tự pixel trong frame
        hdr = b'\x55\xAA' + struct.pack('>I', pixel_offset)[1:] 
        
        end_idx = min(pixel_offset + pixels_per_packet, total_pixels)
        payload = flat[pixel_offset:end_idx].tobytes()
        
        sock.sendto(hdr + payload, addr)
        pixel_offset = end_idx

def main():
    print("--- Mako G-040 to FPGA Bridge (60 FPS) ---")
    
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1) # Bật quyền gửi Broadcast
    dest_addr = (FPGA_IP, FPGA_PORT)
    
    try:
        with VmbSystem.get_instance() as vmb:
            cams = vmb.get_all_cameras()
            if not cams:
                print("Error: No Camera found in the network!")
                return
            
            cam = cams[0]
            print(f"Connecting to: {cam.get_id()}...")
            
            with cam:
                # Camera Configuration
                try:
                    cam.ExposureAuto.set('Continuous')
                    cam.AcquisitionFrameRateEnable.set(True)
                    cam.AcquisitionFrameRate.set(TARGET_FPS)
                    print(f"Set FPS: {TARGET_FPS} OK")
                except Exception as e:
                    print(f"Config Warning: {e}")

                # Optimize GeV packet size
                try:
                    stream = cam.get_streams()[0]
                    stream.GVSPAdjustPacketSize.run()
                    while not stream.GVSPAdjustPacketSize.is_done():
                        pass
                    print("Network Packet Size Optimized.")
                except Exception as e:
                    print(f"PacketSize Optimization Skip: {e}")
                
                print("Streaming started. Press Ctrl+C to stop.")
                
                last_time = time.time()
                frame_count = 0
                
                # Frame acquisition loop
                for frame in cam.get_frame_generator(limit=None, timeout_ms=2000):
                    start_process = time.time()
                    if frame.get_status() == FrameStatus.Complete:
                        img = frame.as_opencv_image()
                        img_resized = cv2.resize(img, (IMG_W, IMG_H))
                        rgb565 = rgb888_to_rgb565(img_resized)
                        send_frame(sock, dest_addr, rgb565)
                        
                        frame_count += 1
                        if time.time() - last_time >= 1.0:
                            print(f"Streaming FPS: {frame_count}")
                            frame_count = 0
                            last_time = time.time()

    except KeyboardInterrupt:
        print("\nStopped by user.")
    except Exception as e:
        print(f"System Error: {e}")
        import traceback
        traceback.print_exc()
    finally:
        sock.close()
        cv2.destroyAllWindows()

if __name__ == "__main__":
    main()
