"""隔离重生成旧字库，逐字节比较；不覆写当前构建输入。"""
from pathlib import Path
import importlib.util
import builtins
import argparse

ROOT=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser()
parser.add_argument('--output',type=Path,required=True)
args=parser.parse_args()
args.output.mkdir(parents=True,exist_ok=True)
original_open=builtins.open
generated={}
def isolated_open(file,mode='r',*positional,**kwargs):
    path=Path(file).resolve()
    if 'w' in mode:
        if ROOT not in path.parents: raise RuntimeError(f'生成器写入越界: {path}')
        destination=args.output/path.relative_to(ROOT)
        destination.parent.mkdir(parents=True,exist_ok=True)
        generated[path]=destination
        return original_open(destination,mode,*positional,**kwargs)
    return original_open(file,mode,*positional,**kwargs)

def load(name):
    spec=importlib.util.spec_from_file_location(name,ROOT/'scripts'/f'{name}.py')
    mod=importlib.util.module_from_spec(spec);spec.loader.exec_module(mod)
    return mod

ascii_font=load('gen_font');cjk=load('gen_font_cjk')
try:
    builtins.open=isolated_open
    glyphs=ascii_font.rasterize()
    ascii_font.emit_verilog(glyphs);ascii_font.emit_bram_hex(glyphs)
    chars=cjk.build_charset(cjk.load_strings()+[text for _,text in cjk.WINDOWS])
    glyphs=cjk.rasterize(chars);index={ch:i+1 for i,ch in enumerate(chars)}
    cjk.emit_rom(index,glyphs);cjk.emit_text_rom(index);cjk.emit_bram_hex(index,glyphs)
finally:
    builtins.open=original_open
for original,destination in generated.items():
    if original.read_bytes()!=destination.read_bytes(): raise RuntimeError(f'生成物不同步: {original}')
print(f'LEGACY_GENERATED PASS {len(generated)} byte-identical isolated outputs')
