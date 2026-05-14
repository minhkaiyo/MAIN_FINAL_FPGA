import socket
import time

# Script này gửi Broadcast, không cần ARP, không cần Admin
PORT = 1234
msg = b'\x55' * 100

sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)

print("--- Đang gửi Broadcast tới cổng 1234 ---")
print("Cậu nhìn xem HEX trên FPGA có hiện 5555 không nhé!")

try:
    while True:
        sock.sendto(msg, ('<broadcast>', PORT))
        time.sleep(0.1) # Gửi chậm thôi để quan sát
except KeyboardInterrupt:
    print("Dừng.")
finally:
    sock.close()
