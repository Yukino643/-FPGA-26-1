from pathlib import Path
root=Path(__file__).resolve().parents[4]
t=(root/'sim/tb_audio_waveform.v').read_text(encoding='utf-8')
t=t.replace('tb_audio_waveform','tb_audio_waveform_720')
a=t.index(' wire a,b,c;');b=t.index(' initial begin #',a)
t=t[:a]+''' wire a;
 tb_audio_waveform_720_case #(.RENDER(1)) t0(a);
 initial begin wait(a);$display("TB_AUDIO_WAVEFORM_720 PASS checks=%0d",t0.checks);$finish;end
'''+t[b:]
t=t.replace('WAVE_X=64,WAVE_Y=376,WAVE_WIDTH=512,WAVE_HEIGHT=72','WAVE_X=128,WAVE_Y=576,WAVE_WIDTH=1024,WAVE_HEIGHT=96')
t=t.replace('reg [9:0] x=0;reg [8:0] y=0;', 'reg [10:0] x=0;reg [9:0] y=0;')
t=t.replace('.WAVE_HEIGHT(WAVE_HEIGHT),.DECIMATE(DECIMATE)', '.WAVE_HEIGHT(WAVE_HEIGHT),.DECIMATE(DECIMATE),.VIDEO_WIDTH(1280),.VIDEO_HEIGHT(720),.X_BITS(11),.Y_BITS(10),.PIPELINED_GEOMETRY(1)')
t=t.replace('[8:0]','[9:0]').replace('[17:9]','[19:10]')
t=t.replace('WAVE_WIDTH+40','WAVE_WIDTH+44').replace('waveform_continuous.ppm','waveform_720.ppm')
(root/'sim/tb_audio_waveform_720.v').write_text(t,encoding='utf-8',newline='\n')
