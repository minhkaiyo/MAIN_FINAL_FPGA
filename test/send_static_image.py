import socket
import struct
import time
import numpy as np
import cv2

# --- CẤU HÌNH ---
FPGA_IP = "255.255.255.255"
FPGA_PORT = 1234
WIDTH = 640
HEIGHT = 480

def create_test_image():
    # Tạo nền chuyển sắc (gradient) để dễ thấy màu xám đều
    img = np.zeros((HEIGHT, WIDTH), dtype=np.uint8)
    for y in range(HEIGHT):
        img[y, :] = (y % 256) # Chuyển sắc từ trên xuống dưới
            
    # Vẽ lưới kẻ caro 50x50 để phát hiện nếu dòng bị lệch/chéo
    for y in range(0, HEIGHT, 50):
        img[y:y+3, :] = 255 # Vạch ngang trắng
    for x in range(0, WIDTH, 50):
        img[:, x:x+3] = 255 # Vạch dọc trắng
        
    # Vẽ khung viền màn hình (để check mất viền)
    img[0:5, :] = 255
    img[-5:, :] = 255
    img[:, 0:5] = 255
    img[:, -5:] = 255
    
    return img

def main():
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)

    img = create_test_image()
    cv2.imshow("Test Image Sent to FPGA", img)
    cv2.waitKey(1)
    
    print("Đang gửi ảnh tĩnh (Test Pattern) tới FPGA...")
    
    # Gửi liên tục ảnh tĩnh để màn hình giữ hình (vì Triple Buffering tự refresh)
    # Ta gửi tầm 50 khung hình để check sự ổn định.
    try:
        frame = 0
        while True:
            for y in range(HEIGHT):
                row_data = img[y].tobytes()
                row_header = struct.pack('>H', y) # 2-byte tọa độ y tuyệt đối
                payload = row_header + row_data
                
                sock.sendto(payload, (FPGA_IP, FPGA_PORT))
                
                # CỰC KỲ QUAN TRỌNG: Delay 0.1ms để Windows KHÔNG DROP GÓI TIN!
                time.sleep(0.0001) 
                
            frame += 1
            print(f"Đã gửi xong frame thứ {frame}")
            time.sleep(0.03) # Tương đương 30fps
            
            # Cập nhật GUI cv2
            if cv2.waitKey(1) & 0xFF == ord('q'):
                break
    except KeyboardInterrupt:
        pass
        
    print("Dừng phát.")

if __name__ == "__main__":
    main()
