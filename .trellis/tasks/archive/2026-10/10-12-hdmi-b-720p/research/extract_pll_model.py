from pathlib import Path

source = Path(r'D:\Anlogic\TD_6.2.1_Engineer_6.2.168.116\sim_release\eg4\eg_phy_pll.v')
text = source.read_bytes().decode('utf-8-sig')
# 原文件先给出完整明文功能模型，末尾另带商业仿真器加密视图。
# Icarus 不支持 pragma protect，仿真只使用官方已提供的明文视图。
plain = text.split('`pragma protect begin_protected', 1)[0]
if plain.count('module ') == 0 or not plain.rstrip().endswith('endmodule'):
    raise RuntimeError('官方明文 PLL 模型不完整')
# 官方模型把 scalar load_reg 端口又用作内部5位脉冲总线，Icarus拒绝。
# 内部信号独立命名；不改变divider、锁定算法或静态时钟参数。
for old, new in (
    ('wire [4:0] sclk, load_reg, rotate, direct;', 'wire [4:0] sclk, load_reg_internal, rotate, direct;'),
    ('assign load_reg  = {5{ld_reg_i}};', 'assign load_reg_internal = {5{ld_reg_i}};'),
):
    if plain.count(old) != 1:
        raise RuntimeError('官方模型版本变化：无法应用端口兼容修复')
    plain = plain.replace(old, new)
for index in range(5):
    plain = plain.replace(f'.shot(load_reg[{index}])', f'.shot(load_reg_internal[{index}])')
destination = Path(__file__).parent / 'eg_phy_pll_functional.v'
destination.write_text(plain.replace('\r\n', '\n'), encoding='utf-8', newline='\n')
