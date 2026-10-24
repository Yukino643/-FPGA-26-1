# Implementation record

## Changes

- Removed the production `640 -> 800` renderer coordinate path and restored integer 640-raster coordinates.
- Removed the fixed 48-row top and bottom crop and restored the board-proven full 640x480 scaler path.
- Restored the 512-column waveform geometry and single BRAM curve table.
- Changed the reset/default transition from horizontal slide to cross-fade.
- Forced the display scroll request to zero whenever a horizontal transition is not active.
- Extended `tb_disp_path` to check two stable frames after every transition and assert that both read engines have zero stable-frame scroll.

## Build artifact

- `td_prj/av_media_Runs/phy_1/av_media.bit`
- Generated: 2026-10-10 20:20:58 Asia/Shanghai
- Size: 643592 bytes

## Remaining review

Flash the new bitstream and verify all three images, black OSD glyph edges, KEY2 switching, and two minutes of stable display on both HDMI outputs.
