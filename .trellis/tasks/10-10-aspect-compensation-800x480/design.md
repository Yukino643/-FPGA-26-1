# Design: 800x480 aspect compensation

## Boundaries

- The raster generator, HDMI encoder timing, framebuffer geometry, and display-page protocol remain 640x480.
- The existing SDRAM source frame remains a 640x480 image in BMP bottom-up row order. Compensation is applied only when the scaler locks a new job's source configuration.
- A combinational x-coordinate mapper converts active-raster coordinates 0..639 to logical canvas coordinates 0..799. It is placed beside `pixel_pos_gen` so the top can map the existing delayed coordinates without changing framebuffer reads.
- UI modules consume the mapped x at the same pipeline stage as their current x input. The display mixer and frame-buffer read path continue using the unmodified 640-wide coordinate.

## Image crop

Add scaler parameters for top and bottom source-row cropping, defaulting to zero so standalone users retain current behavior. At the scaler start event, latch the source width unchanged, reduce the source height by the configured crop rows, and add `crop_top * ceil(source_width/2)` RGB565 words to the source base. This accounts for two 16-bit pixels per 32-bit memory word and preserves BMP bottom-up row addressing. The top-level scaler instance uses 48 rows for both crop parameters, producing a 384-row source window that still fills the existing 640x480 destination.

Reject invalid crop geometry in simulation checks. The production images are 640x480; no image asset or framebuffer storage is rewritten.

## Logical UI coordinates

Map each active x coordinate with nearest-integer rounding:

`x800 = floor((5 * x640 + 2) / 4)`

This covers both endpoints, 0 and 799, without adding a clock cycle. Keep current coordinate pipeline registers and add corresponding mapped-coordinate registers alongside them. The OSD uses 800-wide placement constants for its right-side mode and uptime labels. The waveform moves from `(64, 376, 512, 72)` to `(80, 376, 640, 72)`. The monitor compositor and emergency renderer also receive mapped coordinates so their 8x16 glyphs and horizontal geometry are not widened by the panel.

## Timing and interfaces

- Do not map `main_x` before the display mixer; that coordinate is an SDRAM/FIFO column index in the 0..639 address domain.
- Map the coordinate from the same source sample that currently feeds each renderer. Register mapped x alongside `x_d1/x_d2/x_d3`; do not insert a new RGB or DE stage.
- For the monitor output, map raw `mon_x` combinationally before `monitor_compositor`; its existing one-cycle internal glyph pipeline and the top-level `mon_de_d1` alignment remain unchanged.
- The waveform's curve-table width grows to 640 columns. Split its table at column 512 into two synchronous 9K BRAM banks, delay the bank-select bit with the BRAM read, and keep each bank on one write port. Confirm the inferred BRAM count and existing blanking-time budget still pass.

## Failure cases and tradeoffs

- Applying a 48-row base offset in pixel units instead of 32-bit words would shift reads by 96 rows; calculate with `(width+1)/2` words per line and test the production width.
- Cropping height without offsetting the base would read the wrong part of the bottom-up BMP. The source row mapping must prove both endpoints.
- Mapping `main_x` before the display mixer would read the wrong FIFO columns and break image transitions. Keep the address path untouched.
- Scaling only the OSD but not the waveform or diagnostic renderer would leave some elements stretched. Keep all renderer coordinate paths covered.
- The mapper is a nearest-sample conversion. Some logical columns are skipped in the 640-pixel output and are restored by the monitor's 1.25x stretch; use circle and grid checks to bound the rasterization error.
