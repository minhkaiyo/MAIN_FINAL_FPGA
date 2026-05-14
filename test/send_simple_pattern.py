import socket
import struct
import time
import numpy as np
import cv2

# --- CONFIG ---
FPGA_IP = "255.255.255.255" # Broadcast (hoặc IP tĩnh của mạch)
FPGA_PORT = 1234
WIDTH = 640
HEIGHT = 480

def create_test_pattern():
    # Tạo một mảng ảnh đen 640x480
    img = np.zeros((HEIGHT, WIDTH), dtype=np.uint8)
    
    # Vẽ các sọc dọc trắng cách nhau 32 pixel
    for x in range(0, WIDTH, 32):
        img[:, x:x+16] = 255 # Cột chẵn sáng, cột lẻ tối
        
    # Thêm số hàng để dễ debug (mỗi dòng tăng độ sáng)
    for y in range(HEIGHT):
        img[y, 0:32] = (y % 256) # 32 pixel đầu tiên là gradient dọc
        
    return img

def main():
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    
    print("Tạo Pattern Sọc Trắng Đen (Mono8) để Test VGA Pipeline...")
    pattern = create_test_pattern()
    
    cv2.imshow("Preview Pattern (Nhan Q de thoat)", pattern)
    cv2.waitKey(1)
    
    frame_num = 0
    
    try:
        while True:
            t0 = time.time()
            # Gửi 480 dòng
            for row in range(HEIGHT):
                # GVSP Header giả: Frame_ID (1 byte) + Row (2 byte) + Payload (640 byte)
                # FPGA Parser cấu hình: header[0:1] không quan tâm, header[2] = row_high, header[3] = row_low
                # Wait, FPGA Parser check byte_cnt.
                # Byte 0: row_high
                # Byte 1: row_low
                # Payload: 640 bytes
                
                row_high = (row >> 8) & 0xFF
                row_low = row & 0xFF
                
                packet = struct.pack('>BB', row_high, row_low) + pattern[row, :].tobytes()
                sock.sendto(packet, (FPGA_IP, FPGA_PORT))
                
            frame_num += 1
            t1 = time.time()
            fps = 1.0 / (t1 - t0)
            print(f"Sent Frame {frame_num} - {fps:.1f} FPS")
            
            # Gửi chậm lại để dễ quan sát (FPGA lưu ở SDRAM nên không sợ)
            time.sleep(0.05)
            
            if cv2.waitKey(1) & 0xFF == ord('q'):
                break
                
    except KeyboardInterrupt:
        print("Stopped by User.")
    finally:
        sock.close()
        cv2.destroyAllWindows()

if __name__ == "__main__":
    main()
