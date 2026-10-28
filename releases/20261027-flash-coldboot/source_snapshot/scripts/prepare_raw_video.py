"""把离线视频制作为RV16帧流；不会修改原视频或TF卡。"""
from pathlib import Path
import argparse
import hashlib
import json
import struct
import subprocess
import tempfile

from PIL import Image, ImageDraw

WIDTH, HEIGHT, FPS = 320, 180, 10
FRAME_BYTES = WIDTH * HEIGHT * 2


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--input', type=Path, required=True)
    parser.add_argument('--ffmpeg', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--seconds', type=float, default=10)
    parser.add_argument('--audio', action='store_true', help='RV16 v2: 48kHz/16bit/双声道原轨')
    args = parser.parse_args()
    if not args.input.is_file() or not args.ffmpeg.is_file() or not 0 < args.seconds <= 60:
        raise ValueError('输入视频、FFmpeg路径或片长无效')
    args.output.mkdir(parents=True, exist_ok=True)
    dest = args.output / 'VIDEO.R16'
    if dest.exists():
        raise FileExistsError('不覆盖既有素材：' + str(dest))
    with tempfile.TemporaryDirectory(prefix='rv16-') as tmp:
        raw = Path(tmp) / 'frames.rgb565'
        proc = subprocess.run([str(args.ffmpeg), '-nostdin', '-hide_banner', '-loglevel', 'error',
            '-i', str(args.input), '-t', str(args.seconds), '-map', '0:v:0', '-an',
            '-vf', 'fps=10,scale=320:180:force_original_aspect_ratio=decrease,'
                   'pad=320:180:(ow-iw)/2:(oh-ih)/2,setsar=1,vflip',
            '-pix_fmt', 'rgb565le', '-f', 'rawvideo', str(raw)], capture_output=True)
        if proc.returncode:
            raise RuntimeError('视频转换失败：' + proc.stderr.decode('utf-8', errors='replace'))
        payload = raw.read_bytes()
        pcm = b''
        if args.audio:
            count, rem = divmod(len(payload), FRAME_BYTES)
            if rem or not 1 <= count <= 65535:
                raise ValueError('视频帧数据不完整')
            audio_file = Path(tmp) / 'original.s16le'
            proc = subprocess.run([str(args.ffmpeg), '-nostdin', '-hide_banner', '-loglevel', 'error',
                '-i', str(args.input), '-map', '0:a:0', '-vn', '-af',
                f'aresample=48000,apad,atrim=end_sample={count * 4800},asetpts=N/SR/TB',
                '-ar', '48000', '-ac', '2', '-c:a', 'pcm_s16le', '-f', 's16le', str(audio_file)], capture_output=True)
            if proc.returncode:
                raise RuntimeError('原视频音轨转换失败：' + proc.stderr.decode('utf-8', errors='replace'))
            pcm = audio_file.read_bytes()
            if len(pcm) != count * 4800 * 4:
                raise ValueError('原轨样本数不等于视频帧数×4800')
    count, rem = divmod(len(payload), FRAME_BYTES)
    if rem or not 1 <= count <= 65535:
        raise ValueError('转换后的帧大小或数量不合法')
    header = struct.pack('<4sHHHHIIII', b'RV16', 2 if args.audio else 1, WIDTH, HEIGHT, FPS,
                         count, FRAME_BYTES, 512, 1)
    if args.audio:
        header += struct.pack('<IIII', 1 + count * 225, count * 4800, 48000, 0x00020010)
    header = header.ljust(512, b'\0')
    pcm_padded = pcm + bytes((-len(pcm)) % 512)
    with dest.open('xb') as dst:
        dst.write(header)
        dst.write(payload)
        dst.write(pcm_padded)
    data = dest.read_bytes()
    if data[:512] != header or data[512:512+len(payload)] != payload or data[512+len(payload):] != pcm_padded or len(data) % 512:
        raise RuntimeError('素材独立回读不一致')
    sheet = Image.new('RGB', (WIDTH * 4, (HEIGHT + 24) * 3), '#101923')
    draw = ImageDraw.Draw(sheet)
    selected = sorted(set(round(i * (count - 1) / 11) for i in range(12)))
    for pos, n in enumerate(selected):
        frame = payload[n * FRAME_BYTES:(n + 1) * FRAME_BYTES]
        pixels = bytearray(WIDTH * HEIGHT * 3)
        # 独立逐像素解565、翻回正向，避免预览掩盖素材行序/字节序错误。
        for y in range(HEIGHT):
            for x in range(WIDTH):
                word = struct.unpack_from('<H', frame, ((HEIGHT - 1 - y) * WIDTH + x) * 2)[0]
                r, g, b = (word >> 11) & 31, (word >> 5) & 63, word & 31
                i = (y * WIDTH + x) * 3
                pixels[i:i + 3] = bytes(((r << 3) | (r >> 2), (g << 2) | (g >> 4), (b << 3) | (b >> 2)))
        ox, oy = (pos % 4) * WIDTH, (pos // 4) * (HEIGHT + 24)
        sheet.paste(Image.frombytes('RGB', (WIDTH, HEIGHT), bytes(pixels)), (ox, oy))
        draw.text((ox + 6, oy + HEIGHT + 4), f'FRAME {n:03d} / {n / FPS:.1f}s', fill='white')
    sheet.save(args.output / 'contact_sheet.png')
    # 首、次和尾帧扇区夹具供RTL直接消费，十六进制字节一行一个。
    for name, offset, size in [('header', 0, 512), ('frame0', 512, FRAME_BYTES),
                               ('frame1', 512 + min(1, count - 1) * FRAME_BYTES, FRAME_BYTES),
                               ('last', 512 + (count - 1) * FRAME_BYTES, FRAME_BYTES)]:
        (args.output / (name + '.hex')).write_text(
            ''.join(f'{v:02x}\n' for v in data[offset:offset + size]), encoding='ascii', newline='\n')
    meta = {'input': str(args.input.resolve()), 'input_sha256': hashlib.sha256(args.input.read_bytes()).hexdigest(),
            'format': f'RV16 v{2 if args.audio else 1} RGB565 little endian bottom-up, 512-byte header',
            'width': WIDTH, 'height': HEIGHT, 'fps': FPS, 'frames': count,
            'duration_seconds': count / FPS, 'frame_bytes': FRAME_BYTES,
            'frame_sectors': FRAME_BYTES // 512, 'bytes': len(data),
            'sha256': hashlib.sha256(data).hexdigest(), 'audio': args.audio}
    if args.audio:
        meta['audio_format'] = '48000Hz signed16LE stereo'
        meta['audio_sector'] = 1 + count * 225
        meta['audio_samples'] = count * 4800
        meta['audio_pcm_sha256'] = hashlib.sha256(pcm).hexdigest()
    (args.output / 'metadata.json').write_text(json.dumps(meta, ensure_ascii=False, indent=2) + '\n',
                                              encoding='utf-8', newline='\n')
    print(json.dumps(meta, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
