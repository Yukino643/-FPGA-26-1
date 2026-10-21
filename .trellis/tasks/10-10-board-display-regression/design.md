# Design: board display regression recovery

## Root causes

1. The 800x480 assumption was contradicted by the monitor's 16:9 stretch mode. Cropping 48 rows at both ends enlarged the image under the wrong target ratio.
2. Mapping `x640` to `x800` before glyph lookup skipped ROM columns nonuniformly. The monitor then interpolated the already resampled glyphs, producing blurred strokes.
3. Horizontal slide changes every row's SDRAM start address and wraps at the row boundary. It has a larger hardware risk than cross-fade and must not be the default or leak into stable frames.

## Recovery

- Restore the scaler's original full-source path.
- Restore the 640-wide renderer geometry and single 512-column waveform table.
- Set the reset/default transition mode to cross-fade.
- Gate `display_scroll_x` with both `tr_active` and horizontal `slide_axis`.
- Extend display-path verification with explicit stable-frame invariants independent of the DUT address formula.

## Follow-up

After the recovery bitstream passes on hardware, evaluate a standard 1280x720 HDMI mode as a separate task. That is the correct place to remove monitor stretching without damaging source images or text.
