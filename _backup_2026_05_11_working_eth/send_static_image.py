# send_static_image.py
# Send a static test image to FPGA via UDP (RGB332 color)
# Use this to verify VGA display WITHOUT camera

import socket
import struct
import time
import numpy as np

FPGA_IP = "255.255.255.255"
FPGA_PORT = 1234
WIDTH = 640
HEIGHT = 480

def generate_color_bars():
    """Generate standard SMPTE color bar pattern in RGB332"""
    img = np.zeros((HEIGHT, WIDTH), dtype=np.uint8)
    bar_width = WIDTH // 8
    # Colors in RGB332: White, Yellow, Cyan, Green, Magenta, Red, Blue, Black
    colors = [
        0xFF,  # White:   R=111 G=111 B=11
        0xFC,  # Yellow:  R=111 G=111 B=00
        0x1F,  # Cyan:    R=000 G=111 B=11
        0x1C,  # Green:   R=000 G=111 B=00
        0xE3,  # Magenta: R=111 G=000 B=11
        0xE0,  # Red:     R=111 G=000 B=00
        0x03,  # Blue:    R=000 G=000 B=11
        0x00,  # Black:   R=000 G=000 B=00
    ]
    for i, c in enumerate(colors):
        x_start = i * bar_width
        x_end = min((i + 1) * bar_width, WIDTH)
        img[:, x_start:x_end] = c
    return img

def generate_gradient():
    """Generate RGB gradient pattern in RGB332"""
    img = np.zeros((HEIGHT, WIDTH), dtype=np.uint8)
    for y in range(HEIGHT):
        for x in range(WIDTH):
            r = int((x / WIDTH) * 7) & 0x7
            g = int((y / HEIGHT) * 7) & 0x7
            b = int(((x + y) / (WIDTH + HEIGHT)) * 3) & 0x3
            img[y, x] = (r << 5) | (g << 2) | b
    return img

def main():
    import sys
    pattern = sys.argv[1] if len(sys.argv) > 1 else "bars"
    
    print(f"=== Static Image Test ({pattern}) ===")
    
    if pattern == "gradient":
        img = generate_gradient()
    else:
        img = generate_color_bars()
    
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    
    header_struct = struct.Struct('>H')
    
    print(f"[SENDING] {WIDTH}x{HEIGHT} RGB332 image...")
    
    # Send 3 frames to make sure triple buffer catches it
    for frame in range(3):
        for y in range(HEIGHT):
            payload = header_struct.pack(y) + img[y].tobytes()
            sock.sendto(payload, (FPGA_IP, FPGA_PORT))
        time.sleep(0.05)
        print(f"  Frame {frame+1}/3 sent.")
    
    print("[OK] Done! Check VGA display.")
    print("  - Color bars: 8 vertical stripes (W/Y/C/G/M/R/B/K)")
    print("  - Gradient: smooth color transition")

if __name__ == "__main__":
    main()
