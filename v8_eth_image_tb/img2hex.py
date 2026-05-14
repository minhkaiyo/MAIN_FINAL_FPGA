import os
from PIL import Image, ImageDraw, ImageFont

def create_test_image(img_path):
    print("Creating a sample test image...")
    img = Image.new('L', (640, 480), color=0)
    draw = ImageDraw.Draw(img)
    # Draw some shapes to make it recognizable
    draw.rectangle([100, 100, 540, 380], outline=255, width=5)
    draw.ellipse([220, 140, 420, 340], outline=128, width=5)
    draw.line([0, 0, 640, 480], fill=200, width=3)
    draw.line([0, 480, 640, 0], fill=200, width=3)
    img.save(img_path)

def convert_img_to_hex(img_path, hex_path):
    if not os.path.exists(img_path):
        create_test_image(img_path)
        
    img = Image.open(img_path).resize((640, 480)).convert('L') # Convert to Mono8
    pixels = img.load()
    
    with open(hex_path, 'w') as f:
        for y in range(480):
            for x in range(640):
                f.write(f"{pixels[x, y]:02X}\n")
    print(f"Successfully converted '{img_path}' to '{hex_path}' (640x480 Mono8)")

if __name__ == "__main__":
    # You can replace test_image.jpg with your own image!
    convert_img_to_hex("test_image.jpg", "input_image.hex")
