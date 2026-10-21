# 800x480 aspect compensation

## Goal

Keep the existing 640x480 HDMI timing and framebuffer while compensating for a display that forces the input to fill its native 800x480 panel.

## Requirements

- The three root-level TF card images are 640x480 RGB565-compatible BMPs and must fill the panel without horizontal distortion after the monitor stretches the 640x480 signal to 800x480.
- Preserve the HDMI timing, output frame dimensions, display buffer size, SDRAM addresses, image switching, and TF card assets.
- Crop the centered 640x384 portion of each 640x480 source image, removing 48 source rows from the top and bottom, then scale it to the existing 640x480 output frame.
- Draw the main title, mode label, waveform, and uptime against an 800x480 logical canvas, mapping logical horizontal coordinates to the existing 640-pixel raster.
- Preserve pixel, DE, and character-ROM pipeline alignment across every adjusted overlay path.
- Keep the current working-tree changes out of commits unless they are directly required by this task. The original source and worktree remain recoverable from the pre-task backup and patch.

## Acceptance Criteria

- [x] The original 640x480 HDMI timing, 640x480 frame buffers, and SDRAM layout are unchanged.
- [x] Scaler source reads for the production image path stay within source rows 48 through 431, with the row offset calculated from the actual pixels per 32-bit word.
- [x] The scaler still writes exactly 640x480 pixels and completes normally; existing image-switch and frame-commit behavior remains intact.
- [x] The 640-to-800 coordinate map is monotonic, maps 0 to 0 and 639 to 799, and has only one- or two-logical-pixel steps.
- [x] Main OSD, waveform, emergency overlay, and monitor compositor receive coordinates aligned to their corresponding RGB/DE pipelines.
- [x] A synthetic circle/grid check confirms the panel-space geometry is approximately undistorted; a crop check confirms the intended source rows are used.
- [x] Existing image and UI simulation checks pass; the TF-card BMP assets were not available in the checkout for a per-image render review.
- [x] `bash scripts/regression.sh`, `bash scripts/regression.sh --full`, report checks, and the TD project build pass against the current RTL.
- [x] A new bitstream is generated for later board confirmation; physical panel behavior remains unverified until it is flashed and checked.

## Constraints

- Do not change HDMI timing or output resolution.
- Do not edit TF card image data, enlarge the framebuffer, or change SDRAM address assignments.
- Use the existing 800x480 panel assumption; if its actual active area differs, re-evaluate the compensation ratio before changing this task's implementation.
