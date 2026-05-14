# stream_gige_camera.py
# 100+ FPS HIGH-SPEED GIGE STREAMING FOR FPGA
# Mode: vmbpy (Modern Allied Vision SDK)

import vmbpy
import socket
import struct
import time
import numpy as np

# --- CONFIG ---
FPGA_IP = "255.255.255.255"
FPGA_PORT = 1234
WIDTH = 640
HEIGHT = 480
CAM_ID = 'DEV_000F315CE51C'

class FrameHandler:
    def __init__(self, sock, addr):
        self.sock = sock
        self.addr = addr
        self.headers = [struct.pack('>H', y) for y in range(HEIGHT)]
        self.frame_count = 0
        self.t0 = time.time()

    def __call__(self, cam, stream, frame):
        if frame.get_status() == vmbpy.FrameStatus.Complete:
            # Gửi dữ liệu Mono8 thô 640x480
            img_data = frame.as_numpy_ndarray()
            
            for y in range(HEIGHT):
                # Header 2 byte row index + 640 byte pixel data
                self.sock.sendto(self.headers[y] + img_data[y, :].tobytes(), self.addr)
            
            self.frame_count += 1
            now = time.time()
            if now - self.t0 >= 1.0:
                fps = self.frame_count / (now - self.t0)
                print(f"  >>> GIGE STREAMING: {fps:.1f} FPS")
                self.frame_count = 0
                self.t0 = now

        cam.queue_frame(frame)

def main():
    print("=== GigE Modern Stream (vmbpy) ===")
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, 8*1024*1024) 

    with vmbpy.VmbSystem.get_instance() as vmb:
        try:
            cam = vmb.get_camera_by_id(CAM_ID)
        except vmbpy.VmbCameraError:
            print(f"[ERROR] Camera {CAM_ID} not found!")
            return

        with cam:
            # 1. Cấu hình Camera
            try:
                cam.set_pixel_format(vmbpy.PixelFormat.Mono8)
                cam.get_feature_by_name('Width').set(WIDTH)
                cam.get_feature_by_name('Height').set(HEIGHT)
                
                # Cấu hình FPS và Exposure
                try: cam.get_feature_by_name('ExposureAuto').set('Off')
                except: pass
                try: cam.get_feature_by_name('ExposureTimeAbs').set(5000.0)
                except: pass
                try: cam.get_feature_by_name('AcquisitionFrameRateEnable').set(True)
                except: pass
                try: cam.get_feature_by_name('AcquisitionFrameRateAbs').set(60.0)
                except: pass
                try: cam.get_feature_by_name('StreamBytesPerSecond').set(115000000)
                except: pass
                
                print(f"[OK] Camera configured to {WIDTH}x{HEIGHT} Mono8.")
            except Exception as e:
                print(f"[WARN] Some settings failed: {e}")

            handler = FrameHandler(sock, (FPGA_IP, FPGA_PORT))
            
            try:
                cam.start_streaming(handler, buffer_count=10)
                print("[RUNNING] Streaming started. Press Enter to stop...")
                input()
            finally:
                cam.stop_streaming()

if __name__ == "__main__":
    main()
