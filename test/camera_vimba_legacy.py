import numpy as np
import cv2
import socket
import time
import struct
import sys
from vimba import *

# --- CONFIG ---
FPGA_IP   = "255.255.255.255"
FPGA_PORT = 1234
IMG_W, IMG_H = 320, 240
TARGET_FPS   = 20
MAX_PAYLOAD  = 1400
FRAME_INTERVAL = 1.0 / TARGET_FPS

PIXELS_PER_PACKET = (MAX_PAYLOAD - 5) // 2
PACKETS_PER_SLEEP = 6

def rgb888_to_rgb565(img: np.ndarray) -> np.ndarray:
    r = (img[:, :, 2].astype(np.uint16)) >> 3
    g = (img[:, :, 1].astype(np.uint16)) >> 2
    b = (img[:, :, 0].astype(np.uint16)) >> 3
    return (r << 11) | (g << 5) | b

def rgb565_to_bgr8(rgb565: np.ndarray) -> np.ndarray:
    """Decode RGB565 back to BGR8 for PC preview (shows what FPGA sees)"""
    r5 = ((rgb565 >> 11) & 0x1F).astype(np.uint8)
    g6 = ((rgb565 >> 5) & 0x3F).astype(np.uint8)
    b5 = (rgb565 & 0x1F).astype(np.uint8)
    r8 = (r5 << 3) | (r5 >> 2)
    g8 = (g6 << 2) | (g6 >> 4)
    b8 = (b5 << 3) | (b5 >> 2)
    return np.stack([b8, g8, r8], axis=-1)

def send_frame(sock: socket.socket, dest_addr: tuple, rgb565: np.ndarray) -> None:
    sock.sendto(b'\x55\xAA\xFF\xFF\xFF', dest_addr)
    time.sleep(0.001)
    flat = rgb565.flatten()
    total = len(flat)
    pixel_offset = 0
    packet_count = 0
    while pixel_offset < total:
        hdr = b'\x55\xAA' + struct.pack('>I', pixel_offset)[1:]
        end_idx = min(pixel_offset + PIXELS_PER_PACKET, total)
        sock.sendto(hdr + flat[pixel_offset:end_idx].tobytes(), dest_addr)
        pixel_offset = end_idx
        packet_count += 1
        if packet_count % PACKETS_PER_SLEEP == 0:
            time.sleep(0.0005)

def configure_camera(cam) -> None:
    try:
        cam.Width.set(cam.WidthMax.get())
        cam.Height.set(cam.HeightMax.get())
        cam.OffsetX.set(0)
        cam.OffsetY.set(0)
    except: pass
    try:
        cam.AcquisitionFrameRateAbs.set(TARGET_FPS)
    except: pass
    try:
        cam.GVSPAdjustPacketSize.run()
        deadline = time.time() + 5.0
        while not cam.GVSPAdjustPacketSize.is_done():
            if time.time() > deadline: break
            time.sleep(0.05)
    except: pass
    print(f"[INFO] Camera: {cam.Width.get()}x{cam.Height.get()} @ {TARGET_FPS} FPS")

def process_frame(frame):
    """Returns (rgb565, img_bgr_resized) or (None, None)"""
    try:
        raw_data = frame.get_buffer()
        h, w = frame.get_height(), frame.get_width()
        img_raw = np.frombuffer(raw_data, dtype=np.uint8)[:h*w].reshape((h, w))
        img_bgr = cv2.cvtColor(img_raw, cv2.COLOR_BayerGR2BGR)
        img_resized = cv2.resize(img_bgr, (IMG_W, IMG_H))
        return rgb888_to_rgb565(img_resized), img_resized
    except: return None, None

def main():
    print("--- Mako to FPGA Bridge ---")
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, 1024 * 1024)
    dest_addr = (FPGA_IP, FPGA_PORT)
    try:
        with Vimba.get_instance() as vimba:
            cams = vimba.get_all_cameras()
            if not cams:
                print("[ERROR] No camera found!")
                return
            cam = cams[0]
            print(f"[INFO] Connected: {cam.get_id()}")
            with cam:
                configure_camera(cam)
                print("[INFO] Streaming. Press Ctrl+C to stop.")
                frame_count = 0
                fps_timer = time.time()
                last_frame_time = time.time()
                try:
                    while True:
                        try:
                            frame = cam.get_frame(timeout_ms=2000)
                        except: continue
                        if frame.get_status() != FrameStatus.Complete: continue
                        now = time.time()
                        if now - last_frame_time < FRAME_INTERVAL: continue
                        last_frame_time = now
                        rgb565, img_bgr = process_frame(frame)
                        if rgb565 is not None:
                            send_frame(sock, dest_addr, rgb565)
                            frame_count += 1
                            
                            # --- SAVE DEBUG IMAGE (Every 20 frames) ---
                            if frame_count % 20 == 0:
                                cv2.imwrite("d:/App/Code/Du_an/FPGA/MAIN_FINAL/test/debug_pc.jpg", img_bgr)
                                fpga_preview = rgb565_to_bgr8(rgb565)
                                cv2.imwrite("d:/App/Code/Du_an/FPGA/MAIN_FINAL/test/debug_fpga.jpg", fpga_preview)
                                print("[INFO] Debug images saved (debug_pc.jpg, debug_fpga.jpg)")

                        if time.time() - fps_timer >= 1.0:
                            print(f"[FPS] {frame_count}")
                            frame_count = 0
                            fps_timer = time.time()
                except KeyboardInterrupt:
                    print("\n[INFO] Stopped by user.")
                finally:
                    cv2.destroyAllWindows()
    except Exception as e:
        print(f"[FATAL] {e}")
    finally:
        sock.close()
        print("[INFO] Socket closed.")

if __name__ == "__main__":
    main()