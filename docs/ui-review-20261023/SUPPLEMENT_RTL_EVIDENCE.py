"""补充8组合、三句字幕和独立波形；输出仍不作为板拍或动态录像。"""
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
import importlib.util
import hashlib
import json
import shutil

import numpy as np
from PIL import Image

from BUILD_REVIEW_PACKAGE import HERE, ROOT, WORK, IV, VVP, run, write, digest


def reference_module():
    spec=importlib.util.spec_from_file_location('current_osd_reference',ROOT/'scripts/render_main_ui.py')
    mod=importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def capture(name, title, clock, subtitle, preset, rgb, fixture, strip=False):
    output=WORK/'extra'
    output.mkdir(parents=True,exist_ok=True)
    raw=output/(name+'.rgb')
    bench=output/(name+'.v')
    start=664*1280 if strip else 0
    stop=712*1280 if strip else 720*1280
    write(bench,f'''`timescale 1ns/1ps
module tb_review_osd;
reg clk=0,rst=1;always #5 clk=~clk;
reg [10:0] x=0;reg [9:0] y=0;reg [23:0] bg=0;
wire [23:0] out;reg [23:0] pixels[0:921599];integer i,f;
osd_engine_720 dut(.I_clk(clk),.I_rst(rst),.I_vs_pulse(1'b0),
.I_subtitle_cfg(5'd{8+subtitle+2*preset}),.I_x(x),.I_y(y),.I_bg_rgb(bg),
.I_uptime_bcd(24'h123456),.I_mode(2'd1),.I_clock_enable(1'b{clock}),
.I_text_enable(1'b{title}),.O_rgb(out));
initial begin
$readmemh("{fixture.as_posix()}",pixels);
repeat(3)@(negedge clk);rst=0;repeat(3)@(negedge clk);
f=$fopen("{raw.as_posix()}","wb");if(!f)$fatal(1,"open");
for(i={start};i<{stop};i=i+1)begin
@(negedge clk);x=i%1280;y=i/1280;bg=pixels[i];
@(posedge clk);#1;$fwrite(f,"%c%c%c",out[23:16],out[15:8],out[7:0]);end
$fclose(f);$display("REVIEW_OSD_RTL PASS");$finish;end
endmodule
''')
    exe=output/(name+'.vvp')
    sources=[ROOT/'rtl/video'/p for p in ('osd_engine_720.v','osd_text_720.v','subtitle_text_720.v','font_rom_720.v')]
    run([IV,'-g2005','-I',ROOT/'rtl/video','-o',exe,bench,*sources],name+'_compile')
    if 'REVIEW_OSD_RTL PASS' not in run([VVP,exe],name):
        raise RuntimeError('missing RTL marker '+name)
    actual=np.frombuffer(raw.read_bytes(),np.uint8).reshape(((48 if strip else 720),1280,3))
    expected=reference_module().reference(rgb,subtitle,title,clock,preset=preset)
    if strip:
        expected=expected[664:712]
    if not np.array_equal(actual,expected):
        raise RuntimeError('independent pixel mismatch '+name)
    file='images/'+name+'.png'
    Image.fromarray(actual).save(HERE/file)
    print(name+' independent pixel PASS',flush=True)
    return {'file':file,'kind':'current OSD RTL, independent pixel-reference checked',
            'title':bool(title),'clock':bool(clock),'subtitle':bool(subtitle),'preset':preset,
            'waveform':False,'pixel_checks':int(actual.shape[0]*actual.shape[1]),
            'limits':'not board capture; static reset phase; waveform off',
            'input':'constant white' if strip else 'same RGB565-expanded BEACH720 photo as light OSD',
            'source_crop':[0,664,1280,712] if strip else [0,0,1280,720]}


def waveform():
    exe=WORK/'waveform_review.vvp'
    run([IV,'-g2005','-DSIMULATION','-s','tb_audio_waveform_720','-o',exe,
         ROOT/'sim/tb_audio_waveform_720.v',ROOT/'rtl/video/promax_audio_waveform.v'],'waveform_compile')
    if 'TB_AUDIO_WAVEFORM_720 PASS' not in run([VVP,exe],'waveform'):
        raise RuntimeError('waveform missing PASS')
    im=Image.open(WORK/'waveform_720.ppm').convert('RGB')
    if im.size!=(1072,104):
        raise RuntimeError('waveform crop size')
    im.save(HERE/'images/waveform_current_RTL.png')
    src=ROOT/'sim/tb_audio_waveform_720.v'
    dst=HERE/'source_snapshot/sim/tb_audio_waveform_720.v'
    shutil.copy2(src,dst)
    return {'file':'images/waveform_current_RTL.png','kind':'current waveform RTL and mathematical/raster reference',
            'bench':'sim/tb_audio_waveform_720.v','source_crop':[112,568,1184,672],
            'input':'synthetic PCM; constant RGB #876543; DECIMATE=4 fixture, top uses120',
            'limits':'not real WAV, not board capture, not composed over photo; static final test scene'}


def main():
    protected=[p for folder in ('rtl','constraints','scripts','sim')
               for p in (ROOT/folder).rglob('*') if p.is_file() and '__pycache__' not in str(p)]
    before={str(p):digest(p) for p in protected}
    rgb=np.array(Image.open(reference_module().SOURCE/'BEACH720.BMP').convert('RGB'),np.uint8)
    for ch,bits in enumerate((5,6,5)):
        v=rgb[:,:,ch]>>(8-bits)
        rgb[:,:,ch]=(v<<(8-bits))|(v>>(2*bits-8))
    white=np.full((720,1280,3),255,np.uint8)
    white_fixture=WORK/'extra_white.hex'
    write(white_fixture,'ffffff\n'*(1280*720))
    captures=[]
    with ThreadPoolExecutor(max_workers=4) as pool:
        jobs=[]
        for t in (0,1):
            for c in (0,1):
                for s in (0,1):
                    jobs.append(pool.submit(capture,f'hdmi_b_T{t}C{c}S{s}_OSD_RTL',t,c,s,0,
                                            rgb,WORK/'main/light_input.hex'))
        for preset in range(3):
            jobs.append(pool.submit(capture,f'subtitle_preset_{preset+1}_white_RTL',0,0,1,preset,
                                    white,white_fixture,True))
        jobs.append(pool.submit(waveform))
        for job in jobs:
            captures.append(job.result())
    prov_path=HERE/'evidence/IMAGE_PROVENANCE.json'
    prov=json.loads(prov_path.read_text(encoding='utf-8'))
    names={item['file'] for item in captures}
    prov=[item for item in prov if item['file'] not in names]+captures
    write(prov_path,json.dumps(prov,ensure_ascii=False,indent=2)+'\n')
    hash_path=HERE/'evidence/SOURCE_SHA256.json'
    hashes=json.loads(hash_path.read_text(encoding='utf-8'))
    hashes['sim/tb_audio_waveform_720.v']=digest(ROOT/'sim/tb_audio_waveform_720.v')
    write(hash_path,json.dumps(hashes,ensure_ascii=False,indent=2)+'\n')
    if before!={str(p):digest(p) for p in protected}:
        raise RuntimeError('product input changed')
    vpath=HERE/'evidence/PACKAGE_VERIFICATION.json'
    ver=json.loads(vpath.read_text(encoding='utf-8'))
    ver.update({'extra_osd_combinations':8,'subtitle_white_strips':3,'waveform_rtl_crop':1,
                'extra_osd_pixel_checks':8*1280*720+3*1280*48,'source_snapshot_files':len(hashes)})
    write(vpath,json.dumps(ver,ensure_ascii=False,indent=2)+'\n')
    print('SUPPLEMENT PASS',flush=True)


if __name__=='__main__':
    main()
