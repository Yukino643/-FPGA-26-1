from pathlib import Path
import xml.etree.ElementTree as ET

root = Path(r'D:\FPGA\code\example')
file = root / 'rtl/pll/video_pll.v'
text = file.read_bytes().decode('utf-8-sig')
replacements = {
    '.FIN("50.000000")': '.FIN("27.000000")',
    '.REFCLK_DIV(2)': '.REFCLK_DIV(4)', '.FBCLK_DIV(1)': '.FBCLK_DIV(11)',
    '.CLKC0_DIV(40)': '.CLKC0_DIV(10)', '.CLKC0_CPHASE(39)': '.CLKC0_CPHASE(9)',
    '.CLKC1_DIV(8)': '.CLKC1_DIV(2)', '.CLKC1_CPHASE(7)': '.CLKC1_CPHASE(1)',
}
for old, new in replacements.items():
    if text.count(old) != 1:
        raise RuntimeError(f'PLL 配置前提已变化: {old}')
    text = text.replace(old, new)
text = '// 720p: reference=27MHz, pixel=74.25MHz, serial=371.25MHz, VCO=742.5MHz.\n' + text
file.write_text(text.replace('\r\n', '\n'), encoding='utf-8', newline='\n')
ipc = root / 'rtl/pll/video_pll.ipc'
tree = ET.parse(ipc)
node = tree.getroot()
for tag, value in [('Page1/input_frequency', '27.0000000000000000MHz'),
                   ('Page3/multiplication_factor', '11'), ('Page3/division_factor', '4')]:
    node.find(tag).text = value
for clock, divide, frequency in zip(node.findall('Page3/clocks/clock'), [10, 2], [74.25, 371.25]):
    clock.find('clock_division_factor').text = str(divide)
    clock.find('clock_frequency').text = f'{frequency:.16f}MHz'
ipc.write_text(ET.tostring(node, encoding='unicode') + '\n', encoding='utf-8', newline='\n')
