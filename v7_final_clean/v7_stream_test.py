# v7_stream_test.py
# Clean, High-Performance Streamer for v7_final_clean FPGA
import vimba
import socket
import struct
import time
import numpy as np
import cv2

# --- CONFIG ---
FPGA_IP = "255.255.255.255" # Broadcast cho nhanh
FPGA_PORT = 1234
WIDTH = 640
HEIGHT = 480
CAM_ID = 'DEV_000F315CE51C' # ID Camera của Minh

class VideoStreamer:
    def __init__(self):
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1) # Cho phép broadcast
        self.addr = (FPGA_IP, FPGA_PORT)
        # Pre-generate row headers to save CPU cycles
        self.headers = [struct.pack('>H', y) for y in range(HEIGHT)]
        self.f_cnt = 0
        self.t0 = time.time()

    def frame_handler(self, cam, frame):
        try:
            if frame.get_status() == vimba.FrameStatus.Complete:
                img = frame.get_buffer()
                # Kiểm tra kích thước thực tế
                actual_size = len(img)
                expected_size = WIDTH * HEIGHT
                
                if actual_size >= expected_size:
                    img_view = memoryview(img).cast('B')
                    for y in range(HEIGHT):
                        packet = self.headers[y] + img_view[y*WIDTH : (y+1)*WIDTH].tobytes()
                        self.sock.sendto(packet, self.addr)
                
                self.f_cnt += 1
                if self.f_cnt % 30 == 0:
                    fps = self.f_cnt / (time.time() - self.t0)
                    print(f"  >>> Streaming: {fps:.1f} FPS (Row 0-479 active)")
                
                time.sleep(0.4) # Nghỉ 200ms ~ 5 FPS
            
            # QUAN TRỌNG: Phải nạp lại frame vào hàng đợi của Vimba
            cam.queue_frame(frame)
        except Exception as e:
            print(f"\n[CALLBACK ERROR] {e}")

def main():
    print("=== GIGABIT VIDEO PIPELINE V7: FINAL CLEAN START ===")
    with vimba.Vimba.get_instance() as vmb:
        try:
            cam = vmb.get_camera_by_id(CAM_ID)
            with cam:
                # Cấu hình Camera tối ưu cho FPGA
                cam.set_pixel_format(vimba.PixelFormat.Mono8)
                cam.Height.set(HEIGHT)
                cam.Width.set(WIDTH)
                
                # Tắt các tính năng không cần thiết để tăng FPS
                try:
                    cam.ExposureAuto.set('Off')
                    cam.ExposureTime.set(20000) # 5ms
                except: pass

                streamer = VideoStreamer()
                cam.start_streaming(handler=streamer.frame_handler, buffer_count=5)
                print("[RUNNING] Pipeline v7 is active. Check VGA screen.")
                input("Press Enter to stop...\n")
                cam.stop_streaming()
        except Exception as e:
            print(f"[ERROR] {e}")

if __name__ == "__main__":
    main()
