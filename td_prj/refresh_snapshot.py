import os

al_path = r'D:\FPGA\code\example\td_prj\av_media.al'
al = open(al_path, encoding='utf-8').read()
prj = al.replace('Path="../', 'Path="../../../')

dirs = [
    r'D:\FPGA\code\example\td_prj\av_media_Runs\syn_1',
    r'D:\FPGA\code\example\td_prj\av_media_Runs\phy_1'
]
for d in dirs:
    out = os.path.join(d, 'av_media.prj')
    open(out, 'w', encoding='utf-8', newline='\n').write(prj)
    print(f'Refreshed: {out}')
