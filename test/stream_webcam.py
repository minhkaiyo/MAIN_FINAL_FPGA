import cv2
import socket
import time

# --- CẤU HÌNH ---
FPGA_IP = "255.255.255.255"  # Phát Broadcast tới cổng mạng cứng
FPGA_PORT = 1234
WIDTH = 640
HEIGHT = 480
FPS_LIMIT = 30 # Hạn chế FPS để tránh cháy bộ đệm (FPGA đang dùng BRAM nội)

def main():
    print("Khởi động Camera...")
    cap = cv2.VideoCapture(0)
    
    # Ép độ phân giải gốc của Webcam (có thể không hỗ trợ tùy loại Cam)
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, WIDTH)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, HEIGHT)

    if not cap.isOpened():
        print("[LỖI] Không thể mở Webcam!")
        return

    # Khởi tạo Socket Broadcast
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    
    # Tăng buffer để gửi nhanh
    try:
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, 1024 * 1024)
    except:
        pass

    print(f"Đang stream tới {FPGA_IP}:{FPGA_PORT} ... (Nhấn 'q' trên màn hình hình ảnh để thoát)")
    
    frame_count = 0
    start_time = time.time()

    while True:
        ret, frame = cap.read()
        if not ret:
            break

        # Resize về đúng 640x480 và chuyển sang ảnh Đen Trắng (Grayscale 8-bit)
        frame_resized = cv2.resize(frame, (WIDTH, HEIGHT))
        frame_gray = cv2.cvtColor(frame_resized, cv2.COLOR_BGR2GRAY)

        # Trực quan hóa hình ảnh trên máy tính để tiện so sánh với VGA
        cv2.imshow("Webcam to FPGA Stream", frame_gray)
        if cv2.waitKey(1) & 0xFF == ord('q'):
            break

        # Đóng gói và gửi UDP
        # Trong thiết kế đơn giản này: Mỗi một dòng ảnh (640 bytes) sẽ là 1 gói tin
        # Để an toàn hơn ở bản này, ta gộp nhiều dòng lại. (Nhưng MTU tối đa là 1500 byte)
        # Ta gửi mỗi gói tin là đúng 1 dòng (640 bytes)
        for y in range(HEIGHT):
            # Lấy 640 bytes của dòng thứ y
            row_data = frame_gray[y].tobytes()
            
            # Đỉnh cao Alignment: Gắn thêm 2-byte chứa tọa độ dòng (y) vào đầu payload!
            import struct
            row_header = struct.pack('>H', y) # Big-endian Unsigned Short
            payload = row_header + row_data
            
            # Bắn thẳng xuống FPGA
            sock.sendto(payload, (FPGA_IP, FPGA_PORT))
            
        frame_count += 1
        
        # Giới hạn FPS
        time.sleep(1.0 / FPS_LIMIT)

        # In log tốc độ
        if time.time() - start_time >= 1.0:
            print(f"Streaming FPS: {frame_count}")
            frame_count = 0
            start_time = time.time()

    cap.release()
    sock.close()
    cv2.destroyAllWindows()

if __name__ == "__main__":
    main()
