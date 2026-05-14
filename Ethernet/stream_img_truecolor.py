"""
Stream ảnh 640×480 RGB565 HIGH COLOR (65,536 màu) qua UDP → DE2i-150 FPGA → SDRAM → VGA

Đây là chế độ CHẤT LƯỢNG TỐI ĐA mà SDRAM controller 100MHz có thể hỗ trợ ổn định.
So sánh:
  - RGB332:  256 màu    → 1 byte/pixel  → 4 pixel/word → 160 word/line
  - RGB565:  65,536 màu → 2 byte/pixel  → 2 pixel/word → 320 word/line  ← CHỌN
  - RGB888:  16.7M màu  → 4 byte/pixel  → 1 pixel/word → 640 word/line  ← VƯỢT BĂNG THÔNG

Giao thức: [Magic 0x55 0xAA] [Pixel Offset 3 byte BE] [Pixel Data RGB565]
"""
import os, socket, time, sys
from PIL import Image, ImageOps

UDP_IP   = "255.255.255.255"
UDP_PORT = 12345
W, H     = 640, 480
PIXELS_PER_PACKET = 500   # Phải chẵn (2 pixel = 1 SDRAM word). 500 pix × 2 byte = 1000 byte/gói

print("=" * 60)
print("  STREAM ẢNH CHẤT LƯỢNG CAO NHẤT: RGB565 - 65,536 MÀU")
print("  Giới hạn tối đa thực tế của DE2i-150 SDRAM Controller")
print("=" * 60)

d = os.path.dirname(os.path.abspath(__file__))
for ext in ["jpg","jpeg","png","bmp","webp"]:
    p = os.path.join(d, f"test.{ext}")
    if os.path.exists(p):
        image_path = p
        break
else:
    print(f"❌ Không tìm thấy test.jpg/png tại {d}")
    sys.exit(1)

print(f"📷 Đang xử lý: {image_path}")
img = Image.open(image_path)
img = ImageOps.exif_transpose(img)
img = img.convert("RGB")

# Center crop 4:3
w, h = img.size
ratio = W / H
if w/h > ratio:
    nw = int(h * ratio); left = (w-nw)//2; img = img.crop((left, 0, left+nw, h))
elif w/h < ratio:
    nh = int(w / ratio); top = (h-nh)//2; img = img.crop((0, top, w, top+nh))
img = img.resize((W, H), Image.LANCZOS)

# ===============================================
# RGB565 encode: RRRRR GGGGGG BBBBB (16 bit)
# Gửi Little-Endian: byte thấp trước, byte cao sau
# FPGA parser ghép: word[15:0] = {hi_byte, lo_byte} = pixel 0
#                    word[31:16] = {hi_byte, lo_byte} = pixel 1
# ===============================================
pixels = bytearray()
for y in range(H):
    for x in range(W):
        r, g, b = img.getpixel((x, y))
        pixel_16 = ((r & 0xF8) << 8) | ((g & 0xFC) << 3) | (b >> 3)
        pixels.append(pixel_16 & 0xFF)         # Low byte
        pixels.append((pixel_16 >> 8) & 0xFF)  # High byte

total_pixels = W * H
total_bytes = len(pixels)
print(f"✅ Ảnh sẵn sàng: {W}×{H} = {total_pixels:,} pixels")
print(f"✅ Dung lượng RGB565: {total_bytes / 1024:.1f} KB ({total_bytes / 1024 / 1024:.2f} MB)")
print(f"   So với RGB332: gấp {total_bytes / total_pixels:.0f}× dung lượng, gấp 256× số màu!")

sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)

input("\n--- Nhấn ENTER để truyền ảnh High Color RGB565 ---\n")

t0 = time.time()
off = 0    # Pixel offset (không phải byte offset!)
npkt = 0

while off < total_pixels:
    n = min(PIXELS_PER_PACKET, total_pixels - off)
    # Đảm bảo n là bội của 2 (2 pixel = 1 SDRAM word)
    if n % 2 != 0 and off + n < total_pixels:
        n -= 1

    # Lấy chunk bytes (2 byte per pixel)
    chunk = pixels[off * 2 : (off + n) * 2]

    # Header 5 byte: [Magic 0x55, 0xAA] + [Pixel Offset 3 byte Big-Endian]
    header = bytearray([
        0x55, 0xAA,
        (off >> 16) & 0xFF,
        (off >> 8)  & 0xFF,
         off        & 0xFF
    ])

    sock.sendto(header + chunk, (UDP_IP, UDP_PORT))
    off += n
    npkt += 1
    time.sleep(0.002)  # Nhịp nghỉ cho FPGA FIFO

dt = time.time() - t0
print(f"🎉 Truyền thành công! {npkt} gói, {total_pixels:,} pixels, {dt:.2f}s")
print(f"📺 Xem màn hình VGA — Sắc nét gấp 256 lần so với RGB332!")
