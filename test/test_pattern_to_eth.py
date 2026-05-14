import numpy as np
import cv2
import socket
import time
import struct

# --- CẤU HÌNH HỆ THỐNG ---
FPGA_IP   = "255.255.255.255" # Gửi Broadcast để FPGA chắc chắn nhận được
FPGA_PORT = 1234
IMG_W, IMG_H = 320, 240
TARGET_FPS   = 60
MAX_PAYLOAD  = 1400

def rgb888_to_rgb565(img):
    r = (img[:,:,0] >> 3).astype(np.uint16)
    g = (img[:,:,1] >> 2).astype(np.uint16)
    b = (img[:,:,2] >> 3).astype(np.uint16)
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
    print("--- FPGA v2 Test Pattern Generator (60 FPS) ---")
    print(f"Sending to {FPGA_IP}:{FPGA_PORT} via UDP Broadcast...")
    
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1) # Cho phép gửi Broadcast
    dest_addr = (FPGA_IP, FPGA_PORT)
    
    # Tạo ảnh dải màu (Rainbow)
    rainbow = np.zeros((IMG_H, IMG_W, 3), dtype=np.uint8)
    for x in range(IMG_W):
        rainbow[:, x, :] = [x % 256, (x*2) % 256, (x*3) % 256]
    
    offset = 0
    try:
        while True:
            start_time = time.time()
            
            # Tạo hiệu ứng màu chạy để test Triple Buffer
            test_img = np.roll(rainbow, offset, axis=1)
            offset = (offset + 2) % IMG_W
            
            # Convert & Send
            rgb565 = rgb888_to_rgb565(test_img)
            send_frame(sock, dest_addr, rgb565)
            
            # Control FPS
            elapsed = time.time() - start_time
            time.sleep(max(0, 1.0/TARGET_FPS - elapsed))
            
            if offset % 20 == 0:
                print(f"Streaming Test Pattern... (Frame offset: {offset})", end='\r')

    except KeyboardInterrupt:
        print("\nStopped.")
    finally:
        sock.close()

if __name__ == "__main__":
    main()
