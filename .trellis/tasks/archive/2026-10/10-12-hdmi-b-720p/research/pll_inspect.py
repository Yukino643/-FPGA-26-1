from pathlib import Path
import re
import fitz

task = Path(__file__).resolve().parent
guide = Path(r'D:\FPGA\HX4S20_Contest_202606\6_EG4S20数据手册\PLL用户指南.pdf')
with fitz.open(guide) as document:
    text = '\n'.join(f'PAGE {index + 1}\n' + page.get_text() for index, page in enumerate(document))
    (task / 'pll-guide.txt').write_text(text, encoding='utf-8', newline='\n')
    document[1].get_pixmap(matrix=fitz.Matrix(1.5, 1.5)).save(str(task / 'pll-limits.png'))
    print(text[:16000])
binary = Path(r'D:\Anlogic\TD_6.2.1_Engineer_6.2.168.116\bin\IpTool.exe').read_bytes()
strings = [s.decode('ascii') for s in re.findall(rb'[ -~]{8,}', binary)]
hits = [s for s in strings if any(k in s.lower() for k in ['usage:', 'command line', 'commandline', '--help', 'ipc file', 'batch mode'])]
print('IPTOOL CLI STRINGS:', '\n'.join(hits[:30]))
for index, value in enumerate(strings):
    if value.startswith('Usage:'):
        print('USAGE CONTEXT:', '\n'.join(strings[max(0, index - 10):index + 55]))
position = binary.find(b'Usage:')
print('FULL USAGE:', '\n'.join(s.decode('ascii') for s in re.findall(rb'[ -~]{2,}', binary[position:position + 600])))
wide_strings = [s.decode('utf-16le') for s in re.findall(rb'(?:[ -~]\x00){2,}', binary)]
print('WIDE CLI:', '\n'.join(s for s in wide_strings if s.startswith('-') and len(s) < 70))
