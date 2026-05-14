import cv2
import socket
import struct
import numpy as np
import time

# ==========================================
# CẤU HÌNH TRUYỀN PHÁT UDP ETHERNET JUMBO
# ==========================================
UDP_IP = "255.255.255.255"  
UDP_PORT = 12345
sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
# Gia tăng bộ đệm đẩy mạng để không rớt gói FPS cao
sock.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, 2048000)

W, H = 640, 480
PIXELS_PER_PACKET = 500   # Phải chẵn! 500 pixel × 2 byte = 1000 byte/gói (khớp RGB565)
TOTAL_PIXELS = W * H

def main():
    print("Khởi động Webcam HD 640x480 — Chế độ RGB565 High Color...")
    cap = cv2.VideoCapture(1) # 1: Camera ngoài/ngoại vi (Đổi lại 0 nếu cần)
    
    # Ép camera lấp đầy cỡ màn hình yêu cầu và cấu hình FPS
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, W)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, H)
    cap.set(cv2.CAP_PROP_FPS, 30)
    
    if not cap.isOpened():
        print("Lỗi: Không thể tìm thấy hoặc lấy quyền truy cập Camera!")
        return

    print("Đang phát luồng trực tiếp RGB565! Nhấn phím 'q' trên cửa sổ Camera để thoát.")
    
    # Biến tính FPS
    prev_time = time.time()
    frames = 0
    
    while True:
        ret, frame = cap.read()
        if not ret:
            print("Lỗi đọc luồng khung hình từ cảm biến máy ảnh.")
            break
            
        frame = cv2.resize(frame, (W, H), interpolation=cv2.INTER_LINEAR)
        
        # OpenCV format: BGR
        b = frame[:, :, 0].astype(np.uint16)
        g = frame[:, :, 1].astype(np.uint16)
        r = frame[:, :, 2].astype(np.uint16)
        
        # ========================================================
        # NUMPY VECTORIZED RGB565: RRRRR GGGGGG BBBBB (16-bit)
        # 65,536 màu — Khớp chính xác format FPGA đã nâng cấp
        # ========================================================
        pixel_565 = ((r & 0xF8) << 8) | ((g & 0xFC) << 3) | (b >> 3)
        
        # Tách thành 2 byte: Low byte trước, High byte sau (Little-Endian)
        lo = (pixel_565 & 0xFF).astype(np.uint8)
        hi = ((pixel_565 >> 8) & 0xFF).astype(np.uint8)
        
        # Xen kẽ 2 mảng byte thành chuỗi [lo0, hi0, lo1, hi1, ...]
        interleaved = np.empty((H, W, 2), dtype=np.uint8)
        interleaved[:, :, 0] = lo
        interleaved[:, :, 1] = hi
        pixel_bytes = interleaved.tobytes()
        
        # Bắn trực tiếp qua UDP — KHÔNG sleep() trong vòng lặp gói tin!
        for i in range(0, TOTAL_PIXELS, PIXELS_PER_PACKET):
            n = min(PIXELS_PER_PACKET, TOTAL_PIXELS - i)
            # 2 byte per pixel → slice theo byte
            data_chunk = pixel_bytes[i * 2 : (i + n) * 2]
            
            # Header: Magic [0x55, 0xAA] + Pixel Offset Big-Endian (3 byte)
            header = struct.pack('>H', 0x55AA) + bytes([(i >> 16) & 0xFF, (i >> 8) & 0xFF, i & 0xFF])
            packet = header + data_chunk
            
            sock.sendto(packet, (UDP_IP, UDP_PORT))
            
        # =========================================
        # Tính điểm FPS Live
        # =========================================
        frames += 1
        now = time.time()
        
        # Điều tốc nhẹ 1 chút giữa các bức ảnh để trống khoang đệm Cache
        # (Chỉ tạo delay giữa các FRAME, không delay giữa các PACKET)
        time.sleep(0.004) 
        
        if now - prev_time >= 1.0:
            print(f">> Streaming FPS: {frames} khung hình / s")
            frames = 0
            prev_time = now
            
        # Hiển thị trên màn hình Laptop để test đối chiếu thật/ảo
        cv2.imshow('PC Webcam Reference (Press q to Quit)', frame)
        if cv2.waitKey(1) & 0xFF == ord('q'):
            break

    # Trả tài nguyên cho Windows
    cap.release()
    cv2.destroyAllWindows()

if __name__ == "__main__":
    main()
