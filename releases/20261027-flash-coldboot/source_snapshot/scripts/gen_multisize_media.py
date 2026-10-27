"""生成板级多分辨率验收图；只写工程素材目录，不操作TF卡。"""
from pathlib import Path
import struct
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / 'media/multisize_test'


def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    for name, width, height in [('TEST640', 640, 480), ('TEST800', 800, 600), ('TESTODD', 641, 479)]:
        image = Image.new('RGB', (width, height), '#112331')
        draw = ImageDraw.Draw(image)
        font = ImageFont.truetype('C:/Windows/Fonts/arial.ttf', max(18, height // 20))
        title_font = ImageFont.truetype('C:/Windows/Fonts/arialbd.ttf', max(26, height // 13))
        for x in range(0, width, 40):
            draw.line((x, 0, x, height - 1), fill='#345368')
        for y in range(0, height, 40):
            draw.line((0, y, width - 1, y), fill='#345368')
        draw.rectangle((0, 0, width - 1, height - 1), outline='#ffffff', width=3)
        for label, box, color in [
            ('TOP LEFT', (6, 6, width // 3, 56), '#c54242'),
            ('TOP RIGHT', (width * 2 // 3, 6, width - 7, 56), '#2b9570'),
            ('BOTTOM LEFT', (6, height - 57, width // 3, height - 7), '#305eb8'),
            ('BOTTOM RIGHT', (width * 2 // 3, height - 57, width - 7, height - 7), '#97722b')]:
            draw.rectangle(box, fill=color)
            draw.text((box[0] + 6, box[1] + 12), label, font=font, fill='white')
        radius = height // 4
        cx, cy = width // 2, height // 2
        draw.ellipse((cx - radius, cy - radius, cx + radius, cy + radius), outline='#ffd166', width=5)
        draw.line((cx - radius, cy, cx + radius, cy), fill='#ffd166', width=2)
        draw.line((cx, cy - radius, cx, cy + radius), fill='#ffd166', width=2)
        draw.text((cx, cy - 30), f'{width} x {height}', font=title_font, fill='white', anchor='mm')
        draw.text((cx, cy + 28), 'KEEP ASPECT RATIO', font=font, fill='white', anchor='mm')
        target = OUTPUT / f'{name}.BMP'
        image.save(target, format='BMP')
        # 从最终文件头独立检查，避免PNG改后缀或意外生成32bit素材。
        header = target.read_bytes()[:54]
        if header[:2] != b'BM' or struct.unpack_from('<ii', header, 18) != (width, height):
            raise RuntimeError(f'BMP尺寸错误: {target}')
        if struct.unpack_from('<HI', header, 28) != (24, 0):
            raise RuntimeError(f'需要未压缩BMP24: {target}')
        with Image.open(target) as reread:
            reread.load()
            if reread.mode != 'RGB' or reread.getpixel((0, 0)) != (255, 255, 255):
                raise RuntimeError(f'BMP回读失败: {target}')
        print(f'MEDIA PASS {target} {width}x{height} BMP24')


if __name__ == '__main__':
    main()
