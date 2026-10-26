"""独立解析发布RV16，并重新解码原MP4比对视频和PCM，不导入素材生成器。"""
from pathlib import Path
import array
import hashlib
import json
import math
import struct
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
ASSET = ROOT / 'build/media_audio/media/big-blue-fish/VIDEO.R16'
ORIGINAL = Path('D:/FPGA/音频/big-blue-fish.mp4')
FFMPEG = ROOT / 'build/raw_video/tools/imageio_ffmpeg/binaries/ffmpeg-win-x86_64-v7.1.exe'


def sha(data):
    return hashlib.sha256(data).hexdigest()


def decode(arguments, output):
    proc = subprocess.run([str(FFMPEG), '-nostdin', '-hide_banner', '-loglevel', 'error',
                           '-i', str(ORIGINAL), *arguments, str(output)], capture_output=True)
    if proc.returncode:
        raise RuntimeError('独立FFmpeg解码失败：' + proc.stderr.decode('utf-8', errors='replace'))
    return output.read_bytes()


def main():
    data = ASSET.read_bytes()
    if len(data) < 512 or len(data) % 512:
        raise ValueError('RV16长度不足或非整扇区')
    magic, version, w, h, fps, frames, frame_bytes, offset, flags = struct.unpack_from('<4sHHHHIIII', data)
    audio_sector, samples, rate, fmt = struct.unpack_from('<IIII', data, 28)
    if (magic, version, w, h, fps, offset, flags, rate, fmt) != (b'RV16', 2, 320, 180, 10, 512, 1, 48000, 0x00020010):
        raise ValueError('RV16发布头字段不符合硬件契约')
    if not 1 <= frames <= 65535 or frame_bytes != w * h * 2 or samples != frames * rate // fps:
        raise ValueError('帧大小/数量或音画长度不一致')
    start = audio_sector * 512
    if start != offset + frames * frame_bytes or any(data[44:512]):
        raise ValueError('音轨偏移或保留头字段错误')
    pcm_end = start + samples * 4
    if len(data) != ((pcm_end + 511) // 512) * 512 or any(data[pcm_end:]):
        raise ValueError('文件末端越界或补齐字节非零')
    pcm = data[start:pcm_end]
    with tempfile.TemporaryDirectory(prefix='rv16-independent-') as folder:
        decoded_pcm = decode(['-map', '0:a:0', '-vn', '-af',
            f'aresample=48000,apad,atrim=end_sample={samples},asetpts=N/SR/TB',
            '-ar', '48000', '-ac', '2', '-c:a', 'pcm_s16le', '-f', 's16le'],
            Path(folder) / 'audio.pcm')
        decoded_video = decode(['-t', '10', '-map', '0:v:0', '-an', '-vf',
            'fps=10,scale=320:180:force_original_aspect_ratio=decrease,'
            'pad=320:180:(ow-iw)/2:(oh-ih)/2,setsar=1,vflip',
            '-pix_fmt', 'rgb565le', '-f', 'rawvideo'], Path(folder) / 'video.rgb565')
    if pcm != decoded_pcm or data[offset:start] != decoded_video:
        raise RuntimeError('RV16视频或音轨与原MP4独立重解码不一致')
    old = (ROOT / 'build/raw_video/media/big-blue-fish/VIDEO.R16').read_bytes()
    if old[512:] != data[offset:start]:
        raise RuntimeError('v2视频帧与板测v1视频帧不一致')
    values = array.array('h', pcm)
    if sys.byteorder != 'little':
        values.byteswap()
    rms = math.sqrt(sum(int(v) ** 2 for v in values) / len(values))
    if not rms:
        raise RuntimeError('原轨全静音，不能作为有声视频验收素材')
    report = {'pass': True, 'file_sha256': sha(data), 'input_sha256': sha(ORIGINAL.read_bytes()),
              'bytes': len(data), 'frames': frames, 'duration_seconds': frames / fps,
              'video_bytes': len(decoded_video), 'video_sha256': sha(decoded_video),
              'pcm_bytes': len(pcm), 'pcm_sha256': sha(pcm), 'stereo_samples': samples,
              'audio_sector': audio_sector, 'pcm_min': min(values), 'pcm_max': max(values),
              'pcm_rms': rms, 'zero_padding': len(data) - pcm_end,
              'independent_mp4_decode_match': True, 'board_tested_v1_frames_match': True,
              'hardware_tested': False}
    output = ROOT / 'build/media_audio/asset_verification.json'
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8', newline='\n')
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
