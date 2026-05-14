import vmbpy
import time
import socket

# --- CẤU HÌNH ---
FPGA_IP = "192.168.1.100"
FPGA_PORT = 1234
TARGET_FPS = 20
PACKET_SIZE = 1400

def ip_to_int(ip_str):
    parts = [int(x) for x in ip_str.split('.')]
    return (parts[0] << 24) + (parts[1] << 16) + (parts[2] << 8) + parts[3]

def main():
    print("--- MAKO G-040C DIRECT TO FPGA ---")
    
    with vmbpy.VmbSystem.get_instance() as vmb:
        try:
            # Ép Vimba kết nối thẳng vào IP của Camera, bỏ qua bước tìm kiếm Broadcast
            with vmb.get_camera_by_id("192.168.1.164") as cam:
                print(f"Đã kết nối Camera: {cam.get_name()}")
                
                # Mở khóa toàn quyền
                cam.set_access_mode(vmbpy.AccessMode.Exclusive)
            
            try:
                # Ép Camera chuyển luồng Video thẳng về IP của FPGA
                # GevSCDA = Stream Channel Destination Address
                cam.get_feature_by_name('GevSCDA').set(ip_to_int(FPGA_IP))
                # GevSCPHostPort = Destination Port
                cam.get_feature_by_name('GevSCPHostPort').set(FPGA_PORT)
                # GevSCPSPacketSize = Packet Size
                cam.get_feature_by_name('GevSCPSPacketSize').set(PACKET_SIZE)
                
                print(f"[OK] Đã cấu hình luồng Video bắn về {FPGA_IP}:{FPGA_PORT}")
            except Exception as e:
                print(f"[CẢNH BÁO] Lỗi cấu hình mạng GigE: {e}")

            # Thiết lập định dạng
            try:
                cam.Width.set(320)
                cam.Height.set(240)
                cam.PixelFormat.set('Mono8')
                print("[OK] Đã set 320x240 Mono8")
            except Exception as e:
                print(f"[CẢNH BÁO] Lỗi cấu hình hình ảnh: {e}")

            try:
                cam.AcquisitionFrameRateEnable.set(True)
                cam.AcquisitionFrameRate.set(TARGET_FPS)
                print(f"[OK] Đã set {TARGET_FPS} FPS")
            except:
                pass

            # Khởi động luồng
            print("\n🚀 Bắt đầu xả Video... Vui lòng nhìn màn hình VGA!")
            cam.AcquisitionStart.run()
            
            print("Nhấn Ctrl+C để dừng Camera...")
            try:
                while True:
                    time.sleep(1)
            except KeyboardInterrupt:
                print("\nĐang dừng Camera...")
                cam.AcquisitionStop.run()
        except vmbpy.VmbCameraError as e:
            print(f"[LỖI] Không thể kết nối tới Camera IP 192.168.1.164: {e}")
            print("Gợi ý: Rút nguồn Camera ra cắm lại để Reset Control Channel, vì có thể FPGA đã lỡ khóa nó rồi!")

if __name__ == "__main__":
    main()
