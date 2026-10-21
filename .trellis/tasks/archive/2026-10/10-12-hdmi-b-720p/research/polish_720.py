from pathlib import Path
root=Path(__file__).resolve().parents[4]
p=root/'rtl/top/top_tf_hdmi_audio.v'
t=p.read_text(encoding='utf-8')
for old,new in (
    ('物理 KEY4：短按转场，长按应急','物理 KEY4：长按进入/退出应急'),
    ('HDMI_A TMDS（副通道监视台，W2 新增）','HDMI_A TMDS（720p首版暂停）'),
    ('// 缩放完成 toggle → video 域 2FF（供转场控制器提交）。\n// 源缓存写完只允许启动 scaler，不能提前提交显示页。',
     '// 缩放完成 toggle接口已替换为管理器完整页提交；video域同步事件与稳定页号。\n// 只有解析和writer均成功的事务可发布，不能绕过隔离门。'),
    ('// W6: frame_write_finish → sd_card_clk 域脉冲（src_packer 排空 + scaler 触发）','// writer完成toggle转SD域单拍，送完整页事务隔离门。'),
    ('// bmp_read_g 输出 24bit 像素流 → src_packer 打包 RGB565 → frame_read_write 写 SRC_BUF','// BMP24 → RGB565双像素打包 → frame_read_write写空闲显示页'),
    ('// ===================== TF 多图扫描与缓存（双缓冲，W3 泛化版: 8 图 + 任意分辨率）','// ===================== TF多图扫描与缓存（最多8张，1280×720 BMP24）'),
    ('// ---- W6: 装载写路径 → SRC_BUF（RGB565 打包，scaler 读取源） ----','// ---- RGB565直接显示页写入；BMP垂直方向由writer转换 ----'),
    ('// MEM_BUF_SRC_BASE','// RGB565显示页'),
    ('// 固定用 addr_0','// 本次装载目标页'),
    ('// W6: src_packer 插在 bmp_read_g 输出与 frame_read_write 之间','// src_packer连接解析器与显示页writer'),
    ('// 颜色调整、波形、字库各一拍；RGB、坐标和 DE 必须同拍推进。','// 两拍混合器之后：颜色、波形、字库各一拍；RGB/坐标/DE同拍推进。'),
    ('// 保持你原来的 TF / SDRAM / video 时钟','// TF/SDRAM时钟沿用基线，视频改为准确74.25MHz级联PLL。'),
):
    if old not in t: raise RuntimeError(old)
    t=t.replace(old,new)
p.write_text(t,encoding='utf-8',newline='\n')
p=root/'rtl/pll/video_pll.v'
t=p.read_text(encoding='utf-8')
a=t.index('///////////////////////////////////////////////////////////////////////////////');b=t.index('`timescale',a)
t=t[:a]+'''// 该封装由旧官方生成模板适配TN305_1.1数字参数，未宣称重新经IP Generator生成。
// 输入27MHz，M=11/N=4，CLKC0反馈；VCO742.5MHz，输出74.25/371.25MHz。
// 已用官方功能模型与TD实际综合/布线验证；实物PLL锁定仍需上板复核。
'''+t[b:]
p.write_text(t,encoding='utf-8',newline='\n')
print('Corrected current-path comments without changing logic')
