from pathlib import Path
root=Path(__file__).resolve().parents[4]
t=(root/'sim/tb_video_pipeline.v').read_text(encoding='utf-8')
t=t.replace('tb_video_pipeline','tb_video_pipeline_720').replace('always #20','always #6.734')
t=t.replace('reg main_de_al=0, vs=0;','reg mix_de=0, mix_vs=0;')
t=t.replace('main_de_al','mix_de').replace('main_x','mix_x').replace('main_y','mix_y')
t=t.replace('[9:0] mix_x','[10:0] mix_x').replace('[8:0] mix_y','[9:0] mix_y')
t=t.replace('reg_video_pipeline.vh','reg_video_pipeline_720.vh').replace('==639','==1279')
t=t.replace('x<640','x<1280').replace('mix_y=100+row','mix_y=row==0 ? 100:710')
t=t.replace('got!=1280','got!=2560').replace('TB_VIDEO_PIPELINE PASS','TB_VIDEO_PIPELINE_720 PASS')
(root/'sim/tb_video_pipeline_720.v').write_text(t,encoding='utf-8',newline='\n')
print('Created actual-top 720p pipeline check')
