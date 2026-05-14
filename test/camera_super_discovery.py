import numpy as np
import cv2
import socket
import time
import struct
from vmbpy import VmbSystem, FrameStatus

# --- CONFIG ---
FPGA_IP   = "255.255.255.255"
FPGA_PORT = 1234
IMG_W, IMG_H = 320, 240
TARGET_FPS   = 60
MAX_PAYLOAD  = 1400

def rgb888_to_rgb565(img):
    img_rgb = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
    r = (img_rgb[:,:,0] >> 3).astype(np.uint16)
    g = (img_rgb[:,:,1] >> 2).astype(np.uint16)
    b = (img_rgb[:,:,2] >> 3).astype(np.uint16)
    return (r << 11) | (g << 5) | b

def send_frame(sock, addr, rgb565_data):
    flat = rgb565_data.flatten()
    total_pixels = len(flat)
    pixel_offset = 0
    pixels_per_packet = (MAX_PAYLOAD - 5) // 2
    while pixel_offset < total_pixels:
        hdr = b'\x55\xAA' + struct.pack('>I', pixel_offset)[1:]
        end_idx = min(pixel_offset + pixels_per_packet, total_pixels)
        payload = flat[pixel_offset:end_idx].tobytes()
        sock.sendto(hdr + payload, addr)
        pixel_offset = end_idx

def main():
    print("--- Mako Super Discovery Bridge ---")
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    dest_addr = (FPGA_IP, FPGA_PORT)
    
    with VmbSystem.get_instance() as vmb:
        # Quét mạng liên tục trong 10 giây cho đến khi thấy Cam
        print("Searching for Camera on all interfaces (including Wifi)...")
        cam = None
        for i in range(10):
            cams = vmb.get_all_cameras()
            if cams:
                cam = cams[0]
                break
            print(f"Retrying discovery ({i+1}/10)...")
            time.sleep(1)
        
        if not cam:
            print("Error: No Camera found! Please check Vimba Viewer again.")
            return

        print(f"Found Camera: {cam.get_id()}")
        
        # Mở camera với cấu hình truy cập
        try:
            with cam:
                print(f"Streaming from {cam.get_model()} at 320x240...")
                
                # Thiết lập các tính năng cơ bản
                try:
                    cam.ExposureAuto.set('Continuous')
                    cam.AcquisitionFrameRateEnable.set(True)
                    cam.AcquisitionFrameRate.set(TARGET_FPS)
                except Exception as e:
                    print(f"Feature Set Warning: {e}")

                last_time = time.time()
                frame_count = 0
                
                for frame in cam.get_frame_generator(limit=None, timeout_ms=3000):
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
                            
        except Exception as e:
            print(f"Critical Error: {e}")
            print("Hint: Make sure Vimba Viewer is CLOSED.")

if __name__ == "__main__":
    main()
