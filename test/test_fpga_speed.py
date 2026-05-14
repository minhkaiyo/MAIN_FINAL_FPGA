import socket
import time
import sys

# --- CONFIG ---
FPGA_IP   = "255.255.255.255"  # DÙNG BROADCAST ĐỂ ÉP WINDOWS GỬI GÓI TIN ĐI MÀ KHÔNG CẦN ARP
FPGA_PORT = 1234
PACKET_SIZE = 1400          # Payload size (MTU 1500)
DURATION  = 5               # Test trong 5 giây

def main():
    print(f"--- Bơm dữ liệu (UDP Broadcast Flood) tới mạng ---")
    print(f"Gói tin: {PACKET_SIZE} bytes. Thời gian: {DURATION}s")
    
    payload = b'\x55' * PACKET_SIZE
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    
    # BẬT TÍNH NĂNG BROADCAST CHO SOCKET (RẤT QUAN TRỌNG)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    
    try:
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, 1024 * 1024)
    except:
        pass
        
    print("[INFO] Đang bơm dữ liệu (Thực sự gửi qua dây cáp)...")
    start_time = time.time()
    packets_sent = 0
    
    try:
        while time.time() - start_time < DURATION:
            sock.sendto(payload, (FPGA_IP, FPGA_PORT))
            packets_sent += 1
    except KeyboardInterrupt:
        print("\n[INFO] Bị ngắt bởi người dùng.")
        
    end_time = time.time()
    total_time = end_time - start_time
    total_bytes = packets_sent * PACKET_SIZE
    mbps = (total_bytes * 8) / (total_time * 1e6)
    
    print("\n--- KẾT QUẢ ---")
    print(f"Tổng số gói đã gửi: {packets_sent}")
    print(f"Tốc độ trung bình: {mbps:.2f} Mbps")
    print(f"Băng thông thực tế: {total_bytes / (total_time * 1024 * 1024):.2f} MB/s")
    print("\n--- KIỂM TRA TRÊN FPGA ---")
    print("1. HEX7-4 phải hiện: 5555 (Vì Payload là 0x55)")
    print("2. HEX3-0 phải hiện: 5555 (Nếu MAC xịn đã cấu hình đúng)")
    
    sock.close()

if __name__ == "__main__":
    main()
