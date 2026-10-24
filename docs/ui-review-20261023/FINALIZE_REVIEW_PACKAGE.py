"""只生成图集、审查包清单和ZIP；独立回读校验路径、快照及图像。"""
from pathlib import Path
import base64
import html
import importlib.util
import json
import re
import zipfile

from PIL import Image
from BUILD_REVIEW_PACKAGE import HERE, ROOT, digest, write


def load(name):
    return json.loads((HERE/'evidence'/name).read_text(encoding='utf-8'))


def main():
    prov=load('IMAGE_PROVENANCE.json')
    hashes=load('SOURCE_SHA256.json')
    release=load('RELEASE_SOURCE_SHA256.json')
    matched=[]
    for name,value in hashes.items():
        if digest(ROOT/name)!=value or digest(HERE/'source_snapshot'/name)!=value:
            raise RuntimeError('source snapshot mismatch '+name)
        if name in release:
            if release[name]!=value:
                raise RuntimeError('snapshot differs from latest released source '+name)
            matched.append(name)
    bit=ROOT/'releases/20261023-autoplay-period/av_media.bit'
    if digest(bit)!=load('RELEASE_verification.json')['bit_sha256']:
        raise RuntimeError('released bit hash mismatch')
    sizes={}
    for item in prov:
        path=HERE/item['file']
        with Image.open(path) as im:
            im.load()
            dims=im.size
        expected=(1072,104) if 'waveform_' in path.name else (1280,48) if 'white_RTL' in path.name else (1280,720)
        if dims!=expected:
            raise RuntimeError('image dimensions '+str(path))
        sizes[item['file']]=list(dims)
    for path in (HERE/'images/logical').glob('*.png'):
        with Image.open(path) as im:
            if im.size!=(640,480):
                raise RuntimeError('logic raster dimensions')

    names={
      'menu_program':'节目控制：三列卡片、字幕开启的夹具',
      'menu_peripheral':'外设：READY / IDLE / CNTAB / LED3',
      'menu_playback':'播放按键模式：无焦点、保留底部小提示',
      'menu_screen':'屏幕：默认色彩参数',
      'menu_screen_edit':'屏幕：对比度113%编辑中',
      'menu_program_screen':'节目控制：聚焦屏幕入口',
      'menu_subtitle':'字幕：1/3、NORM、标题OFF',
      'menu_subtitle_edit':'字幕：内容与速度同时pending的夹具',
      'menu_screen_pending':'屏幕：对比度pending，聚焦未改的亮度卡',
      'menu_wait':'节目控制：强制cfg_busy等待态',
      'menu_audio':'音频：100%、静音OFF、波形ON',
      'menu_audio_edit':'音频：50%预览、编辑中',
      'menu_audio_mute':'音频：80%、静音ON、灰色音量条',
    }
    body=[]
    for i,item in enumerate(prov,1):
        file=item['file'];stem=Path(file).stem
        base=stem.removesuffix('_720')
        caption=names.get(base,stem)
        note='菜单当前RTL + 顶层等比坐标映射；非板拍。' if 'menu_' in stem else '当前OSD RTL静态输出；波形关闭，非板拍。'
        if 'waveform' in stem:
            note='独立波形RTL，合成PCM和固定底色；不是实际音乐、照片合成或板拍。'
        if 'white_RTL' in stem:
            note='当前OSD RTL，白底输入；只取y[664,712)，无时间，字幕起始相位。'
        source_link=''
        if 'menu_' in stem:
            source_link=f'<a href="images/logical/{base}_640.png">打开640×480原生逻辑图</a>'
        body.append(f'<section id="img{i}"><h2>{i:02d} · {html.escape(caption)}</h2>'
                    f'<p>{html.escape(note)} {source_link}</p>'
                    f'<a href="{html.escape(file)}"><img loading="lazy" src="{html.escape(file)}" '
                    f'alt="{html.escape(caption)}"></a>'
                    f'<p class="filename">{html.escape(file)} · {sizes[file][0]}×{sizes[file][1]}</p></section>')
    gallery='''<!doctype html>
<html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>炬屏 · 当前UI审美审查图集 · 20261023</title>
<style>
body{margin:0;background:#101419;color:#e9edf2;font:16px/1.65 "Microsoft YaHei",sans-serif}
main{max-width:1328px;margin:auto;padding:24px}h1{font-size:28px}h2{font-size:20px}
p{color:#bfc9d3}a{color:#72cfff}section{margin:36px 0 56px;border-top:1px solid #34404d;padding-top:12px}
img{display:block;max-width:100%;height:auto;background:#000}.filename{font:13px/1.6 monospace}
.note{border-left:3px solid #72cfff;padding:8px 16px;background:#17212c}code{word-break:break-all}
</style><main><h1>炬屏 · 当前 UI 审美审查图集</h1>
<p>2026-10-23 · 13个菜单场景 + 11张照片OSD图（含8组合）+ 3条字幕细图 + 1张波形局部图。</p>
<div class="note">首要标准是美观：请严格检查构图、留白、字体、配色和视觉状态，不以“能运行”代替审美判断。
点击图片打开原尺寸；菜单再比较640×480原生逻辑图。这里没有板拍，没有本轮动态录像。</div>
<p><a href="CURRENT_UI_REVIEW.md">现状报告</a> · <a href="REVIEW_PROMPT.txt">严格审美提示词</a> ·
<a href="REVIEW_RETURN_TEMPLATE.md">返回模板</a> · <a href="evidence/IMAGE_PROVENANCE.json">逐图来源</a></p>
'''+''.join(body)+'</main></html>\n'
    write(HERE/'VISUAL_GALLERY.html',gallery)

    links=[]
    for name in ('README.md','CURRENT_UI_REVIEW.md','REVIEW_RETURN_TEMPLATE.md'):
        path=HERE/name
        data=path.read_bytes()
        if data.startswith(b'\xef\xbb\xbf') or b'\r' in data:
            raise RuntimeError('document encoding/EOL '+name)
        content=data.decode('utf-8',errors='strict')
        for target in re.findall(r'\]\(([^)]+)\)',content):
            if not target.startswith(('http:','https:','#')):
                if not (path.parent/target).exists():
                    raise RuntimeError('broken document link '+target)
                links.append(target)
    for name in ('REVIEW_PROMPT.txt','VISUAL_GALLERY.html','BUILD_REVIEW_PACKAGE.py',
                 'SUPPLEMENT_RTL_EVIDENCE.py','FINALIZE_REVIEW_PACKAGE.py'):
        data=(HERE/name).read_bytes()
        data.decode('utf-8',errors='strict')
        if data.startswith(b'\xef\xbb\xbf') or b'\r' in data:
            raise RuntimeError('owned text encoding/EOL '+name)
    for target in re.findall(r'(?:href|src)="([^"#]+)"',gallery):
        if not (HERE/target).exists():
            raise RuntimeError('broken gallery link '+target)

    spec=importlib.util.spec_from_file_location('font_spec',ROOT/'scripts/gen_font_720.py')
    fontmod=importlib.util.module_from_spec(spec);spec.loader.exec_module(fontmod)
    if len(fontmod.CHARS)!=50 or [len(s) for s in fontmod.PRESETS]!=[14,14,13]:
        raise RuntimeError('reported font/text count mismatch')
    cjk=ROOT/'scripts/gen_monitor_cjk.py'
    spec=importlib.util.spec_from_file_location('cjk_spec',cjk)
    cjkmod=importlib.util.module_from_spec(spec);spec.loader.exec_module(cjkmod)
    if [len(cjkmod.CHARSET),len(cjkmod.EXTRA),len(cjkmod.AUDIO)]!=[32,4,4]:
        raise RuntimeError('reported menu font count mismatch')
    checks={'passed':True,'document_links_checked':len(links),'image_provenance_entries':len(prov),
            'image_dimensions':sizes,'logical_menu_images':len(list((HERE/'images/logical').glob('*.png'))),
            'source_snapshot_matches_live':len(hashes),'snapshot_files_matching_release':len(matched),
            'main_font_cells':len(fontmod.CHARS),'preset_cells':[len(s) for s in fontmod.PRESETS],
            'menu_glyphs_rom_base_extra_logic':[32,4,4],
            'owned_text_utf8_no_bom_lf':True,'released_bit_hash_verified':digest(bit),
            'new_physical_build':False,'new_board_test':False}
    write(HERE/'evidence/INTEGRITY_CHECKS.json',json.dumps(checks,ensure_ascii=False,indent=2)+'\n')

    files=sorted(p for p in HERE.rglob('*') if p.is_file() and p.name!='SHA256SUMS.txt' and '__pycache__' not in str(p))
    write(HERE/'SHA256SUMS.txt',''.join(f'{digest(p)}  {p.relative_to(HERE).as_posix()}\n' for p in files))
    # 从落盘清单重新逐项回读，不以“刚写过所以正确”作为验证。
    for line in (HERE/'SHA256SUMS.txt').read_text(encoding='utf-8').splitlines():
        value,name=line.split('  ',1)
        if digest(HERE/name)!=value:
            raise RuntimeError('manifest mismatch '+name)
    archive=ROOT/'docs/UI_REVIEW_20261023.zip'
    with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
        for path in sorted(HERE.rglob('*')):
            if path.is_file() and '__pycache__' not in str(path):
                z.write(path,path.relative_to(HERE).as_posix())
    with zipfile.ZipFile(archive) as z:
        bad=z.testzip()
        if bad:
            raise RuntimeError('ZIP CRC '+bad)
        for name,value in hashes.items():
            import hashlib
            if hashlib.sha256(z.read('source_snapshot/'+name)).hexdigest()!=value:
                raise RuntimeError('ZIP source hash mismatch '+name)
        entry_count=len(z.namelist())
    write(archive.with_suffix('.zip.sha256'),digest(archive)+'  '+archive.name+'\n')
    print(json.dumps({'passed':True,'images':len(prov),'source_files':len(hashes),
                      'release_matches':len(matched),'zip_entries':entry_count,
                      'zip_bytes':archive.stat().st_size,'zip_sha256':digest(archive)},ensure_ascii=False),flush=True)


if __name__=='__main__':
    main()
