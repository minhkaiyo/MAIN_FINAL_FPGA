import os
import cv2
import numpy as np

def convert_hex_to_mp4(hex_path, mp4_path, num_frames=3):
    if not os.path.exists(hex_path):
        print(f"Error: {hex_path} not found.")
        return

    with open(hex_path, 'r') as f:
        lines = f.readlines()
        
    print(f"Read {len(lines)} pixels from simulation output.")
    
    fourcc = cv2.VideoWriter_fourcc(*'mp4v')
    # FPS = 3.0 de xem cho ro chuyen dong
    out = cv2.VideoWriter(mp4_path, fourcc, 3.0, (640, 480))
    
    idx = 0
    for f_idx in range(num_frames):
        if idx >= len(lines):
            break
            
        frame = np.zeros((480, 640, 3), dtype=np.uint8)
        
        for y in range(480):
            for x in range(640):
                if idx < len(lines):
                    parts = lines[idx].strip().split()
                    if len(parts) == 3:
                        r, g, b = int(parts[0], 16), int(parts[1], 16), int(parts[2], 16)
                        # OpenCV su dung he mau BGR chu khong phai RGB
                        frame[y, x] = [b, g, r]
                    idx += 1
        
        out.write(frame)
        print(f"Reconstructed Frame {f_idx} vao file MP4")
                
    out.release()
    print(f"Hoan thanh! Da tao xong file video MP4: '{mp4_path}'")

if __name__ == "__main__":
    convert_hex_to_mp4("output_log/vga_output.hex", "reconstructed_video.mp4", 3)
