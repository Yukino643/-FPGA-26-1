"""独立回读七张BMP文件头、RGB565展开和原生字模；生成板测图与预览。"""
from pathlib import Path
import struct
import hashlib
import json
from PIL import Image,ImageDraw
import numpy as np
from render_main_ui import reference

ROOT=Path(__file__).resolve().parents[1]
SOURCE=Path('D:/FPGA/音频/图片比例补偿/素材汇总_20261012/处理图')
OUT=ROOT/'build/720p/previews'
OUT.mkdir(parents=True,exist_ok=True)
checks=[];thumbs=[]
for name in ('BEACH720','NAIL720','ROOM720','NIGHT720','NAIL1720','NAIL2720','MONST720'):
    file=SOURCE/(name+'.BMP');data=file.read_bytes()
    width,height=struct.unpack_from('<ii',data,18)
    planes,bpp=struct.unpack_from('<HH',data,26)
    compression=struct.unpack_from('<I',data,30)[0]
    offset=struct.unpack_from('<I',data,10)[0]
    if (width,height,planes,bpp,compression)!=(1280,720,1,24,0) or len(data)!=offset+width*height*3:
        raise RuntimeError(f'不兼容BMP: {file}')
    # 独立按文件存储顺序解码，然后按writer行地址反转。
    bgr=np.frombuffer(data,dtype=np.uint8,offset=offset).reshape(height,width,3)
    rgb=bgr[::-1,:,::-1].copy()
    expanded=np.empty_like(rgb)
    for channel,bits in enumerate((5,6,5)):
        value=rgb[:,:,channel]>>(8-bits)
        expanded[:,:,channel]=(value<<(8-bits))|(value>>(2*bits-8))
    image=Image.fromarray(expanded,'RGB')
    image.save(OUT/(name+'_565.png'))
    wave=Image.open(ROOT/'build/720p/regression/waveform_720.png') if (ROOT/'build/720p/regression/waveform_720.png').is_file() else None
    if wave is not None:
        wave=wave.convert('RGB');mask=Image.eval(wave.convert('L'),lambda value:0)
        a=np.array(wave);selected=(a==[59,240,165]).all(axis=2)|(a==[42,78,88]).all(axis=2)
        mask=Image.fromarray((selected*255).astype(np.uint8));image.paste(wave,(112,568),mask)
    # 软件合成明确标注REFERENCE；真实OSD RTL图由render_main_ui.py生成。
    image=Image.fromarray(reference(np.array(image),True,True,True),'RGB')
    image.save(OUT/(name+'_screen_REFERENCE.png'))
    thumb=image.resize((640,360),Image.Resampling.LANCZOS)
    thumbs.append(thumb)
    checks.append({'name':file.name,'width':width,'height':height,'bits':bpp,'sha256':hashlib.sha256(data).hexdigest(),'evidence':'software reference; not RTL frame or board capture'})
contact=Image.new('RGB',(1280,4*380),(245,245,245))
d=ImageDraw.Draw(contact)
for i,thumb in enumerate(thumbs):
    x=(i%2)*640;y=(i//2)*380;contact.paste(thumb,(x,y+20));d.text((x+12,y+3),checks[i]['name'],fill='black')
contact.save(OUT/'contact.png')
grid=Image.new('RGB',(1280,720),'white');d=ImageDraw.Draw(grid)
for x in range(0,1280,80):d.line((x,0,x,719),fill=(180,180,180))
for y in range(0,720,80):d.line((0,y,1279,y),fill=(180,180,180))
d.ellipse((440,160,840,560),outline='black',width=5)
d.rectangle((0,0,1279,719),outline='red',width=3)
grid.save(OUT/'GRID720.BMP')
(OUT/'verification.json').write_text(json.dumps(checks,ensure_ascii=False,indent=2),encoding='utf-8',newline='\n')
print('PREVIEW720 PASS seven exact BMP, RGB565 decoded, native-font composition, calibration grid')
