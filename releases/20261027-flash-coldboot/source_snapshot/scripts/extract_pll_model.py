"""使用安路公开明文PLL功能模型；只修复官方内部信号重名。"""
from pathlib import Path
import argparse

parser=argparse.ArgumentParser()
parser.add_argument('--output',type=Path,required=True)
args=parser.parse_args()
source=Path('D:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/sim_release/eg4/eg_phy_pll.v')
text=source.read_bytes().decode('utf-8-sig')
plain=text.split('`pragma protect begin_protected',1)[0]
if not plain.rstrip().endswith('endmodule'): raise RuntimeError('官方明文模型不完整')
for old,new in (('wire [4:0] sclk, load_reg, rotate, direct;','wire [4:0] sclk, load_reg_internal, rotate, direct;'),('assign load_reg  = {5{ld_reg_i}};','assign load_reg_internal = {5{ld_reg_i}};')):
    if plain.count(old)!=1: raise RuntimeError('官方库版本变化')
    plain=plain.replace(old,new)
for i in range(5): plain=plain.replace(f'.shot(load_reg[{i}])',f'.shot(load_reg_internal[{i}])')
args.output.write_text(plain.replace('\r\n','\n'),encoding='utf-8',newline='\n')
print('PLL_MODEL PASS official plaintext')
