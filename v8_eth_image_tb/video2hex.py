import os
from PIL import Image, ImageDraw

def create_animated_hex(hex_path, num_frames=3):
    print(f"Creating an animation with {num_frames} frames...")
    
    with open(hex_path, 'w') as f:
        for frame in range(num_frames):
            img = Image.new('L', (640, 480), color=0)
            draw = ImageDraw.Draw(img)
            
            # Draw moving object (a ball bouncing from left to right)
            x_pos = 100 + frame * 150
            draw.rectangle([10, 10, 630, 470], outline=255, width=5)
            draw.ellipse([x_pos, 150, x_pos + 100, 250], fill=180 + frame*30)
            draw.text((x_pos, 280), f"FRAME {frame}", fill=255)
            
            pixels = img.load()
            for y in range(480):
                for x in range(640):
                    f.write(f"{pixels[x, y]:02X}\n")
                    
    print(f"Successfully generated {num_frames} frames to '{hex_path}'")

if __name__ == "__main__":
    create_animated_hex("input_image.hex", 3)
