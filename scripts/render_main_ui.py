"""照片输入真实OSD RTL，独立核对逐像素输出；波形关闭，不冒充板拍。"""
from pathlib import Path
import argparse
import hashlib
import json
import subprocess
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SOURCE = Path('D:/FPGA/音频/图片比例补偿/素材汇总_20261012/处理图')
IV = 'C:/iverilog/bin/iverilog.exe'
VVP = 'C:/iverilog/bin/vvp.exe'
LABEL = '炬屏—双模HDMI多媒体系统'
PRESETS = (LABEL, '双屏协作 一屏操作 一屏呈现', '图片 音乐 字幕 精彩同屏')
CHARS = ' ' + ''.join(dict.fromkeys(
    ''.join((LABEL, '广告模式', '应急模式', '运行 00:00:00')).replace(' ', '') +
    '123456789' + ''.join(PRESETS).replace(' ', '') + '视界'))


def reference(bg, subtitle, text, clock, phase=0, preset=0):
    out = bg.copy()
    mask = np.zeros((720,1280), dtype=bool)
    if text:
        mask[16:64,16:496] = True
        mask[16:64,1104:1264] = True
    if clock:
        mask[664:712,848:1248] = True
    if subtitle:
        mask[664:712,32:1248] = True
    out[mask] = bg[mask] >> 2
    if subtitle:
        out[664:712,32:128] = (14,58,76)
        out[664:666,32:1248] = (56,189,248)
    rows = [int(s,16) for s in (ROOT/'rtl/video/font_720.hex').read_text(encoding='ascii').splitlines()]

    def draw(label, left, top, ink):
        for i,ch in enumerate(label):
            gid=CHARS.index(ch)
            for row in range(32):
                bits=rows[gid*32+row]
                for col in range(32):
                    if bits & (1 << (31-col)):
                        out[top+row,left+32*i+col]=ink
    if text:
        draw(LABEL,32,24,(242,250,255))
        draw('广告模式',1120,24,(143,213,250))
    if clock:
        draw('运行 12:34:56',864,672,(200,247,90))
    if subtitle:
        draw('视界',48,672,(242,250,255))
        # 离线参考按完整1024环形位图裁剪，不依赖RTL的地址或命中。
        strip=np.zeros((32,1024),dtype=bool)
        for i,ch in enumerate(PRESETS[preset]):
            gid=CHARS.index(ch)
            for row in range(32):
                for col in range(32):
                    strip[row,32*i+col]=bool(rows[gid*32+row] & (1<<(31-col)))
        width=688 if clock else 1024
        visible=strip[:,(np.arange(width)+phase)%1024]
        target=out[672:704,144:144+width]
        target[visible]=(242,250,255)
    return out


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--output',required=True)
    args=parser.parse_args()
    output=Path(args.output).resolve()
    output.mkdir(parents=True,exist_ok=True)
    font=(ROOT/'rtl/video/font_720.hex').read_bytes()
    results=[]
    for scene,photo,subtitle in (('light','BEACH720',1),('dark','NIGHT720',1),('subtitle_off','NIGHT720',0)):
        path=SOURCE/(photo+'.BMP')
        rgb=np.array(Image.open(path).convert('RGB'),dtype=np.uint8)
        if rgb.shape!=(720,1280,3): raise RuntimeError(f'素材尺寸不符: {path}')
        # TF显示存储为RGB565；照片输入先按同样位复制展开，仍不等于完整SDRAM仿真。
        for ch,bits in enumerate((5,6,5)):
            v=rgb[:,:,ch]>>(8-bits)
            rgb[:,:,ch]=(v<<(8-bits))|(v>>(2*bits-8))
        values=rgb[:,:,0].astype(np.uint32)<<16 | rgb[:,:,1].astype(np.uint32)<<8 | rgb[:,:,2]
        fixture=output/f'{scene}_input.hex'
        fixture.write_text(''.join(f'{v:06x}\n' for v in values.ravel()),encoding='ascii',newline='\n')
        bench=output/f'{scene}.v'
        raw=output/f'{scene}.rgb'
        bench.write_text(f'''`timescale 1ns/1ps
module tb_main_photo;
reg clk=0,rst=1;always #5 clk=~clk;
reg [10:0] x=0;reg [9:0] y=0;
reg [23:0] bg=0;wire [23:0] rgb;
reg [23:0] pixels[0:921599];
integer i,f;
osd_engine_720 dut(.I_clk(clk),.I_rst(rst),.I_vs_pulse(1'b0),
.I_subtitle_cfg(5'd{8+subtitle}),.I_x(x),.I_y(y),.I_bg_rgb(bg),
.I_uptime_bcd(24'h123456),.I_mode(2'd1),.I_clock_enable(1'b1),.I_text_enable(1'b1),.O_rgb(rgb));
initial begin
$readmemh("{fixture.as_posix()}",pixels);
repeat(3)@(negedge clk);rst=0;repeat(3)@(negedge clk);
f=$fopen("{raw.as_posix()}","wb");if(!f)$fatal(1,"open failed");
for(i=0;i<921600;i=i+1)begin
@(negedge clk);x=i%1280;y=i/1280;bg=pixels[i];
@(posedge clk);#1;$fwrite(f,"%c%c%c",rgb[23:16],rgb[15:8],rgb[7:0]);end
$fclose(f);$display("PHOTO_RTL PASS");$finish;end
endmodule
''',encoding='utf-8',newline='\n')
        exe=output/f'{scene}.vvp'
        sources=[ROOT/'rtl/video'/s for s in ('osd_engine_720.v','osd_text_720.v','subtitle_text_720.v','font_rom_720.v')]
        subprocess.run([IV,'-g2005','-I',str(ROOT/'rtl/video'),'-o',str(exe),str(bench),*map(str,sources)],check=True,capture_output=True)
        proc=subprocess.run([VVP,str(exe)],check=True,capture_output=True,timeout=180)
        (output/f'{scene}.log').write_bytes(proc.stdout+proc.stderr)
        data=raw.read_bytes()
        if len(data)!=1280*720*3: raise RuntimeError(f'RGB输出长度错误 {scene}: {len(data)}')
        actual=np.frombuffer(data,dtype=np.uint8).reshape(720,1280,3)
        expected=reference(rgb,subtitle,True,True)
        if not np.array_equal(actual,expected):
            bad=np.argwhere(np.any(actual!=expected,axis=2))[0]
            raise RuntimeError(f'照片独立像素参考失败 {scene}: yx={bad.tolist()}')
        Image.fromarray(actual).save(output/f'{scene}_OSD_RTL.png')
        results.append({'scene':scene,'source':str(path),'source_sha256':hashlib.sha256(path.read_bytes()).hexdigest(),
                        'pixel_checks':921600,'subtitle':bool(subtitle),'title':True,'clock':True,
                        'evidence':'photo-fed OSD RTL; waveform disabled; not board capture; not complete SDRAM/HDMI simulation'})
        print('MAIN_UI_PHOTO PASS',scene,'921600 pixels',flush=True)
    if hashlib.sha256(font).digest()!=hashlib.sha256((ROOT/'rtl/video/font_720.hex').read_bytes()).digest():
        raise RuntimeError('渲染期间字库变化')
    (output/'verification.json').write_text(json.dumps(results,ensure_ascii=False,indent=2)+'\n',encoding='utf-8',newline='\n')


if __name__=='__main__':
    main()
