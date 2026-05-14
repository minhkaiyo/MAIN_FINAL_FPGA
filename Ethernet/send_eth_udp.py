# send_eth_udp.py
import socket
import sys

UDP_IP = "255.255.255.255" # Phát Broadcast
UDP_PORT = 12345

# Khởi tạo Socket UDP
sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)

print(f"--- CHẾ ĐỘ GỬI GIÁ TRỊ (BYTE) ---")
print(f"Hướng dẫn:")
print("  - Nhập một số từ 0 đến 255 (VD: 165).")
print("  - Board FPGA sẽ hiển thị giá trị này (dạng HEX) lên đèn.")
print("  - Nhấn Ctrl+C để thoát.")
print("-" * 30)

try:
    while True:
        val_str = input("Nhập giá trị muốn gửi (0-255): ").strip()
        if not val_str:
            continue
            
        try:
            val = int(val_str)
            if not (0 <= val <= 255):
                raise ValueError
        except ValueError:
            print("❌ Vui lòng nhập số nguyên từ 0 đến 255!")
            continue

        # Tạo gói tin với byte đầu tiên là giá trị người dùng nhập
        # Chúng ta đệm thêm một ít dữ liệu đằng sau để đảm bảo gói tin đủ lớn
        message = bytes([val]) + b" DE2i-150 Test Packet"
        
        try:
            sock.sendto(message, (UDP_IP, UDP_PORT))
            print(f"✅ Đã gửi giá trị: {val} (Hex: {hex(val).upper()})")
        except Exception as e:
            print(f"❌ Lỗi khi gửi: {e}")
            
        print("Đừng quên nhấn GIỮ KEY0 trên Board để FPGA cập nhật giá trị nhé!")
        print("-" * 30)

except KeyboardInterrupt:
    print("\nKết thúc chương trình.")


