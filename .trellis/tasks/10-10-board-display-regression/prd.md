# Board display regression recovery

## Goal

Restore the last board-proven 640x480 image and UI geometry after the 800x480 compensation produced displaced images and blurred text.

## Requirements

- Display every TF-card BMP with its complete 640x480 source geometry; do not crop or vertically enlarge the image.
- Feed all 8x16 and 16x16 glyph renderers with integer 640-raster coordinates so glyph columns remain uniform.
- Use cross-fade as the default image transition because it does not modify SDRAM read addresses.
- A stable frame must use zero horizontal scroll. Horizontal scroll is legal only while a horizontal transition is active.
- Preserve the existing TF-card format, framebuffer size, SDRAM page addresses, HDMI timing, waveform smoothing, and KEY2 image queue.

## Acceptance Criteria

- [x] Production scaler has zero source crop and writes exactly 640x480 pixels.
- [x] OSD, waveform, emergency renderer, and monitor compositor use original raster coordinates.
- [x] Default transition is cross-fade and stable frames cannot retain a nonzero scroll offset.
- [x] At least two complete post-transition frames are checked against unshifted source columns.
- [x] Basic and full regression, report inspection, TD build, and current-source manifest checks pass.
- [x] New bitstream is explicitly marked as requiring a board recheck.

## Non-goals

- Do not attempt another panel-space aspect compensation in this recovery task.
- Do not change HDMI timing to 720p in this recovery task.
