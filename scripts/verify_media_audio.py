"""有声视频独立单元验证；整条720p管线另由verify_media_runtime覆盖。"""
from pathlib import Path
import importlib.util
import hashlib
import json

ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('runtime',ROOT/'scripts/verify_media_runtime.py')
runtime=importlib.util.module_from_spec(spec)
spec.loader.exec_module(runtime)

def main():
    paths=['scripts/verify_media_audio.py','sim/tb_media_audio.v','sim/tb_audio_frame_budget.v',
        'sim/tb_raw_audio_error.v','sim/media_card_model.v','rtl/audio/wav_read.v',
        'rtl/audio/media_audio_router.v','rtl/sd/fat32_file_sector_mapper.v',
        'rtl/audio/audio_player.v','rtl/mem/afifo_simple.v','rtl/video/video_frame_commit.v']
    inputs={p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in paths}
    runtime.prepare()
    runtime.unit('media_audio',['sim/tb_media_audio.v','sim/media_card_model.v',
        'rtl/audio/wav_read.v','rtl/audio/media_audio_router.v','rtl/sd/fat32_file_sector_mapper.v'])
    runtime.unit('audio_frame_budget',['sim/tb_audio_frame_budget.v','rtl/audio/audio_player.v',
        'rtl/mem/afifo_simple.v','rtl/video/video_frame_commit.v'])
    runtime.unit('raw_audio_error',['sim/tb_raw_audio_error.v','rtl/audio/wav_read.v'])
    for p,digest in inputs.items():
        if hashlib.sha256((ROOT/p).read_bytes()).hexdigest()!=digest:
            raise RuntimeError('验证中输入改变：'+p)
    (runtime.OUT/'audio_results.json').write_text(json.dumps({'pass':True,
        'inputs_sha256':inputs},indent=2)+'\n',encoding='utf-8',newline='\n')

if __name__=='__main__':main()
