import socket
import time
import struct
import cv2
import numpy as np
import math

# Cấu hình IP Broadcast để ép PC gửi qua mọi cổng mà không cần quan tâm ARP
FPGA_IP = "255.255.255.255"
STREAM_PORT = 1234

# Kích thước khung hình theo chuẩn FPGA (320x240 Mono8)
FRAME_W = 320
FRAME_H = 240
PAYLOAD_SIZE = 1000 # Gửi 1000 pixel mỗi gói để an toàn không quá MTU

sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)

def send_gvsp_frame(frame_data, block_id):
    """Gửi 1 frame dữ liệu theo chuẩn GVSP đến FPGA"""
    
    # 1. Gửi gói LEADER (Packet Format = 0x01)
    # Header: Status(2), BlockID(2), Format(1), PktID(3)
    header = struct.pack(">H H B 3B", 0x0000, block_id, 0x01, 0, 0, 0)
    sock.sendto(header, (FPGA_IP, STREAM_PORT))
    time.sleep(0.001)

    # 2. Gửi các gói PAYLOAD (Packet Format = 0x03)
    total_pixels = len(frame_data)
    num_packets = math.ceil(total_pixels / PAYLOAD_SIZE)
    
    for pkt_id in range(1, num_packets + 1):
        start_idx = (pkt_id - 1) * PAYLOAD_SIZE
        end_idx = min(start_idx + PAYLOAD_SIZE, total_pixels)
        chunk = frame_data[start_idx:end_idx]
        
        # PktID 3 bytes
        pkt_id_bytes = pkt_id.to_bytes(3, byteorder='big')
        
        header = struct.pack(">H H B", 0x0000, block_id, 0x03) + pkt_id_bytes
        sock.sendto(header + bytes(chunk), (FPGA_IP, STREAM_PORT))
        
        # Nghỉ một chút xíu để tránh ngập mạng / FPGA mất gói
        time.sleep(0.0001)

    # 3. Gửi gói TRAILER (Packet Format = 0x02)
    header = struct.pack(">H H B 3B", 0x0000, block_id, 0x02, 0, 0, 0)
    sock.sendto(header, (FPGA_IP, STREAM_PORT))
    time.sleep(0.001)

print(f"Đang gửi video test đến FPGA tại {FPGA_IP}:{STREAM_PORT}...")

block_id = 1
while True:
    # --- Tạo ảnh test pattern (Vạch dọc di chuyển) ---
    img = np.zeros((FRAME_H, FRAME_W), dtype=np.uint8)
    
    # Vẽ các dải màu trắng chạy ngang màn hình để dễ nhận biết
    offset = (block_id * 5) % FRAME_W
    cv2.rectangle(img, (offset, 0), (offset + 50, FRAME_H), 255, -1)
    cv2.rectangle(img, ((offset + 100) % FRAME_W, 0), ((offset + 150) % FRAME_W, FRAME_H), 128, -1)
    
    # Hiển thị text Frame ID
    cv2.putText(img, f"Frame: {block_id}", (10, 50), cv2.FONT_HERSHEY_SIMPLEX, 1, 255, 2)
    
    # Chuyển ảnh thành mảng byte 1D
    frame_data = img.flatten()
    
    # Gửi frame
    send_gvsp_frame(frame_data, block_id)
    
    print(f"Đã gửi Frame {block_id}")
    block_id = (block_id + 1) % 65535
    
    # Truyền khoảng 30 fps
    time.sleep(1/30.0)
