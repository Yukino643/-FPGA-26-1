"""将 P0 真实 RTL 菜单栅格映射到 720p，并检查边框及改动边界。"""
from pathlib import Path
import argparse
import hashlib
import json
import re
import shutil
import numpy as np
from PIL import Image

ROOT=Path(__file__).resolve().parents[1]
REG=ROOT/'build/720p/regression'
SCENES={
    'menu_program':(False,0,0,0),
    'menu_peripheral':(True,0,0,0),
    'menu_playback':(False,-1,0,0),
    'menu_screen':(True,0,0,0),
    'menu_screen_edit':(True,1,2,2),
    'menu_program_screen':(False,5,0,0),
    'menu_subtitle':(True,0,0,0),
    'menu_subtitle_edit':(True,1,2,6),
    'menu_screen_pending':(True,0,0,2),
    'menu_wait':(False,0,0,0),
}
COLORS={name:tuple(bytes.fromhex(value)) for name,value in {
    'BG':'07131D','FRAME':'3A6478','FOCUS':'38BDF8','AMBER':'FFB84D'}.items()}

def verify_and_capture(output,baseline):
    status=json.loads((REG/'run_status.json').read_text(encoding='utf-8'))
    results=json.loads((REG/'results.json').read_text(encoding='utf-8'))
    required={'monitor_menu_renderer','monitor_pipeline','monitor_menu_ctrl','monitor_config_regs',
              'screen_color','pipeline720','subtitle_pipeline720','subtitle720','emergency_raster'}
    if not status['complete'] or not required.issubset({r['name'] for r in results if r['pass']}):
        raise RuntimeError('P0所需定向用例未完整通过，拒绝复用旧截图')
    protected=json.loads(baseline.read_text(encoding='utf-8'))
    for name,digest in protected.items():
        if hashlib.sha256((ROOT/name).read_bytes()).hexdigest()!=digest:
            raise RuntimeError('本轮禁止修改的输入发生变化: '+name)
    source=(ROOT/'rtl/video/monitor_menu_renderer.v').read_text(encoding='utf-8')
    if re.search(r'\b(?:dot_hit|dot_row_mask|CARD_SEL|ACCENT|WARN)\b|\bFOOTER\s*=',source):
        raise RuntimeError('旧圆点/旧状态色语义未清除')
    rom=(ROOT/'rtl/video/monitor_cjk_rom.v').read_text(encoding='utf-8')
    if 'glyph_rom [0:1023]' not in rom or 'extra_rom [0:127]' not in rom:
        raise RuntimeError('菜单ROM声明容量变化')
    if len((ROOT/'rtl/video/font_720.hex').read_text(encoding='ascii').splitlines())!=2048:
        raise RuntimeError('HDMI-B字库深度发生变化')
    output.mkdir(parents=True,exist_ok=True)
    edges=[]
    for name,(wide,selected,editing,pending) in SCENES.items():
        ppm=REG/(name+'.ppm')
        if not ppm.is_file():raise RuntimeError('Missing actual RTL capture: '+name)
        a=np.array(Image.open(ppm).convert('RGB'))
        if a.shape!=(480,640,3):raise RuntimeError('Invalid raster '+name)
        a720=np.zeros((720,1280,3),dtype=np.uint8)
        a720[:,160:1120]=a[(np.arange(720)*2//3)[:,None],(np.arange(960)*2//3)[None,:]]
        Image.fromarray(a720).save(output/(name+'_720.png'))
        for idx in range(4 if wide else 6):
            cols=2 if wide else 3
            x0=([32,336] if wide else [24,228,432])[idx%cols]
            y0=[96,288][idx//cols];w=272 if wide else 184
            t=4 if idx==selected else 2
            color=COLORS['AMBER' if ((idx==selected and editing>>idx&1) or (idx!=selected and pending>>idx&1)) else
                         'FOCUS' if idx==selected else 'FRAME']
            # 全部逻辑边框都核对，避免只测卡片中线漏掉角落厚度。
            region=a[y0:y0+160,x0:x0+w]
            mask=np.zeros((160,w),dtype=bool)
            mask[:t,:]=True;mask[-t:,:]=True;mask[:,:t]=True;mask[:,-t:]=True
            if not np.all(region[mask]==color):raise RuntimeError('Logical border mismatch '+name+str(idx))
            px0=160+x0*3//2;py0=y0*3//2;pw=w*3//2;ph=240
            r=a720[py0:py0+ph,px0:px0+pw];pt=t*3//2
            horizontal=np.all(r[120]==color,axis=1)
            vertical=np.all(r[:,pw//2]==color,axis=1)
            actual=[next((j for j,v in enumerate(line) if not v),len(line)) for line in
                    [horizontal,horizontal[::-1],vertical,vertical[::-1]]]
            if actual!=[pt]*4:raise RuntimeError('Physical L/R/T/B width mismatch '+name+str(idx)+str(actual))
            edges.append({'scene':name,'card':idx,'logic_width':t,'physical_sides':actual})
        if name!='menu_playback' and not np.all(a[448:]==COLORS['BG']):
            raise RuntimeError('Menu footer band or hints remain '+name)
        if name=='menu_playback':
            if not (np.all(a[448:456]==COLORS['BG']) and np.all(a[472:480]==COLORS['BG'])):
                raise RuntimeError('Playback hint violates 8px vertical safety margins')
            if (not np.all(a[456:472,:32]==COLORS['BG']) or
                    not np.all(a[456:472,288:]==COLORS['BG']) or
                    np.all(a[456:472,32:288]==COLORS['BG'])):
                raise RuntimeError('Playback hint missing or outside x[32,288)')
    # HDMI-B不在P0改造范围；此图只供边界对照，非本轮主屏新栅格。
    shutil.copy2(ROOT/'docs/ui-review-20261021/images/hdmi_b_dark_reference.png',output/'hdmi_b_subtitle_on_UNCHANGED_REFERENCE.png')
    (output/'regression_status.json').write_text(json.dumps(status,ensure_ascii=False,indent=2)+'\n',encoding='utf-8',newline='\n')
    (output/'regression_results.json').write_text(json.dumps(results,ensure_ascii=False,indent=2)+'\n',encoding='utf-8',newline='\n')
    evidence_paths = [ROOT/'rtl/video/monitor_menu_renderer.v',
                      ROOT/'sim/tb_monitor_menu_renderer.v', ROOT/'sim/tb_monitor_pipeline.v',
                      Path(__file__).resolve()]
    evidence_hashes = {p.relative_to(ROOT).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
                       for p in evidence_paths}
    summary={'passed':True,'mapped_menu_scenes':len(SCENES),'menu_border_checks':edges,
             'playback_hint':{'rect':[32,456,288,472],'vertical_margins':8,
                              'text':'K2 NEXT K3 AUTO HOLD K3 MENU'},
             'implementation_evidence_sha256':evidence_hashes,
             'protected_files':protected,'font_banks':'1024x32 + 128x32 unchanged; HDMI-B 2048x32 unchanged',
             'limitations':['no synthesis/P&R/bitgen; no resource or physical timing claim',
                            'HDMI-B PNG is explicitly unchanged software reference; no 8.6/8.7 work']}
    (output/'verification.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n',encoding='utf-8',newline='\n')
    for name in sorted(required):
        shutil.copy2(REG/(name+'.log'),output/(name+'.log'))
    print('MENU_P0 PASS 10 RTL rasters; every card physical L/R/T/B =3px or 6px; protected inputs unchanged')
    print('Screenshots:',output)

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,default=ROOT/'docs/ui-review-20261021/p0-result')
    parser.add_argument('--baseline',type=Path,default=ROOT/'build/720p/backups/20261021-before-menu-p0/protected-inputs.json')
    args=parser.parse_args()
    verify_and_capture(args.output.resolve(),args.baseline.resolve())
