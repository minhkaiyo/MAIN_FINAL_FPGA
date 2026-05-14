import os
from PIL import Image

def convert_hex_to_img(hex_path, img_path):
    if not os.path.exists(hex_path):
        print(f"Error: {hex_path} not found. Run simulation first!")
        return

    img = Image.new('RGB', (640, 480))
    pixels = img.load()
    
    with open(hex_path, 'r') as f:
        lines = f.readlines()
        
    print(f"Read {len(lines)} pixels from simulation output.")
    if len(lines) < 307200:
        print("Warning: Simulation didn't complete a full frame. Image will be cut off.")
        
    idx = 0
    for y in range(480):
        for x in range(640):
            if idx < len(lines):
                parts = lines[idx].strip().split()
                if len(parts) == 3:
                    # Simulation outputs VGA_R, VGA_G, VGA_B in hex
                    r, g, b = int(parts[0], 16), int(parts[1], 16), int(parts[2], 16)
                    pixels[x, y] = (r, g, b)
                idx += 1
                
    img.save(img_path)
    print(f"Successfully reconstructed image to '{img_path}'. Open it to see the VGA output!")

if __name__ == "__main__":
    convert_hex_to_img("output_log/vga_output.hex", "reconstructed_output.jpg")
