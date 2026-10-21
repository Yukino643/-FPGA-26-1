# Implementation plan

## Ordered work

1. Confirm the backup directory, baseline tag, current feature branch, and pre-existing worktree diff before modifying RTL.
2. Add scaler crop parameters with zero defaults and simulation bounds checks; enable 48-row top/bottom cropping only in the project top-level instance.
3. Add and verify the combinational 640-to-800 coordinate mapper; wire it beside existing x delays for OSD, waveform, emergency rendering, and the HDMI_A monitor compositor.
4. Move the main mode/uptime labels to the right edge of the 800-wide canvas and expand the waveform to the corresponding 800-wide layout. Preserve y positions and existing graphics pipeline latency.
5. Update scaler, OSD, waveform, monitor, and emergency simulations. Add a focused mapper/circle/grid test and confirm cropped source-row bounds in the scaler tests.
6. Regenerate the extracted top-level scaler test include, review the source diff and workspace diff separately, then run `bash scripts/regression.sh`.
7. If the base regression passes, run `bash scripts/regression.sh --full`; inspect `scripts/check_reports.py` output and verify the TD build consumes the same RTL version.
8. Generate the release bitstream and report its exact path and source revision. Stop before board validation; the user will flash the bitstream and confirm it on the physical display.

## Verification commands

- `bash scripts/regression.sh`
- `bash scripts/regression.sh --full`
- The full script's `scripts/check_reports.py` report checks
- TD project build through the repository's `td_prj/build_all.sh` path

## Rollback points

- The complete baseline is `D:\FPGA\backups\pre-aspect-compensation-20261010` and Git tag `backup/pre-aspect-compensation-20261010`.
- Do not restore or reset the worktree to roll back. Revert only task-owned edits if needed, keeping the user's pre-existing `av_media.al` change and untracked files intact.

## Execution result

- Backup directory and pushed baseline tag were verified before implementation.
- The scaler crops rows 48 through 431 from the 640x480 RGB565 source, then writes the existing 640x480 frame buffer. HDMI timing and SDRAM layout remain unchanged.
- The logical x mapper covers 0..639 to 0..799 and is aligned with the existing renderer pipeline stages. The main display path keeps its original framebuffer x coordinate.
- Synthetic circle/grid and crop-bound simulations passed. The TF-card BMP files were not available in the checkout, so their image-specific framing still needs physical review.
- The first base regression exposed stale TD project snapshots (CompileOrder 71 versus the current entry's 68). A current full TD rebuild refreshed both snapshots and the SHA-256 build manifest before tests were repeated.
- `bash scripts/regression.sh`: 45 passed, 0 failed.
- `bash scripts/regression.sh --full`: 46 passed, 0 failed, including synthesis, place-and-route, bit generation, and the final report check.
- Final reports: SWNS -6.565 ns (within the configured baseline tolerance, but still negative), HWNS 0.022 ns, LUT 81.17%, BRAM9K 50/64. No physical panel claim is made before board validation.
- Current bitstream: `td_prj/av_media_Runs/phy_1/av_media.bit`.
