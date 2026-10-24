`timescale 1ns/1ps
module tb_review_fonts;
reg clk=0;always #5 clk=~clk;
reg [5:0] g=0;reg [4:0] r=0;wire[31:0] bits;
reg [7:0] a=0;reg[3:0] ar=0;wire[7:0] ab;
integer i,j,f;
monitor_cjk_rom cjk(.I_clk(clk),.I_index(g),.I_row(r),.O_bits(bits));
font_rom_ascii ascii(.I_clk(clk),.I_char(a),.I_row(ar),.O_bits(ab));
initial begin f=$fopen("D:/FPGA/code/example/build/ui-review-20261024/font_rows.txt","w");if(!f)$fatal(1,"FAIL open");
for(i=0;i<40;i=i+1)for(j=0;j<32;j=j+1)begin
@(negedge clk);g=i;r=j;@(posedge clk);#1;$fwrite(f,"C %0d %0d %08x\n",i,j,bits);end
for(i=32;i<=126;i=i+1)for(j=0;j<16;j=j+1)begin
@(negedge clk);a=i;ar=j;@(posedge clk);#1;$fwrite(f,"A %0d %0d %02x\n",i,j,ab);end
$fclose(f);$display("REVIEW_FONTS PASS");$finish;end
endmodule
