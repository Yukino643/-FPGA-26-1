from pathlib import Path
import re
root=Path(__file__).resolve().parents[4]
path=root/'td_prj/av_media.al'
text=path.read_text(encoding='utf-8')
order=69
def add_order(match):
    global order
    block=match.group(0)
    if 'CompileOrder' not in block:
        block=block.replace('</FileInfo>',f'    <Attr Name="CompileOrder" Val="{order}"/>\n                </FileInfo>')
        order+=1
    return block
text=re.sub(r'<File Path="[^\"]+">\s*<FileInfo>.*?</FileInfo>\s*</File>',add_order,text,flags=re.S)
path.write_text(text,encoding='utf-8',newline='\n')
