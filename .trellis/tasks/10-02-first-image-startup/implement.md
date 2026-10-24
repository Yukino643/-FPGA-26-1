# Implementation Plan

## Ordered Work

1. Preserve the working baseline with the dated backup tag and tracked-diff patch; record the existing dirty paths before editing.
2. Implement a FAT32 indexer with MBR/superfloppy detection, BPB validation, root-directory traversal, `.BMP` short-extension recognition, root-chain traversal, and explicit error/timeout states.
3. Implement a logical file-sector mapper that follows the FAT chain on cluster boundaries, supports repeated logical sector 0, validates cluster/EOC values, and bounds traversal.
4. Integrate both modules in `sd_card_bmp_g`, store cluster/size metadata, route physical sector requests with a latched owner, and preserve the existing BMP/display commit path.
5. Delay the WAV scan start until the first image has committed.
6. Add focused simulations for MBR and superfloppy volumes, directory traversal across sectors/clusters, BMP extension filtering, fragmented file reads, repeated header sector, early EOC, invalid cluster, timeout, and missing files.
7. Register all new RTL in `td_prj/av_media.al` while preserving pre-existing user edits, refresh `syn_1` and `phy_1` project snapshots, and run focused simulations.
8. Run `bash scripts/regression.sh`. Resolve source/snapshot/manifest mismatches against the current source; do not accept an old bit as evidence.
9. Run `bash scripts/regression.sh --full`, inspect `td_prj/reg_build.log`, and confirm the report gate verifies current project snapshots and SHA-256 manifest.
10. Review the final diff, stage only task-owned files/hunks, commit, and push the authorized branch. If network access fails, retain the local commit and backup artifacts.

## Validation Gates

- Simulation: exact directory metadata, exact physical LBAs for fragmented chains, no spurious BMP entries, and bounded termination for malformed media.
- Display-path: `load_done` plus scaler completion must precede buffer commit; bad input must not toggle the displayed buffer.
- Build: Anlogic TD synthesis, place/route, bitgen must be generated from the same current source and canonical project entry.
- Reports: `scripts/check_reports.py` must pass snapshot equality, manifest hashes including the bit, timing, and resource thresholds.
- Hardware timing: record as not measured unless a cold boot is run on the user's board; report simulation/transfer budget separately from this hardware measurement.

## Results (2026-10-02)

- Implemented FAT32 MBR/superfloppy discovery, root-directory BMP filtering, fragmented file-chain mapping, and serialized SD transaction ownership.
- Pipelined BPB geometry arithmetic after the first TD report showed a 19.347 ns, 15-level critical path through the combined FAT span, volume arithmetic, cluster shift, and validation logic.
- Moved the numeric status scanner to `sd_card_clk` at 100 MHz while preserving its 200 Hz per-digit refresh rate; this removed the reported cross-domain hold endpoint.
- Added a BMP-reader SD-error test. FAT32 indexer, fragmented mapper, BMP reader, and `sd_card_bmp_g` elaboration checks passed.
- `bash scripts/regression.sh`: 35/35 checks passed.
- `bash scripts/regression.sh --full`: 36/36 checks passed, including TD synthesis, P&R, bitgen, project snapshot comparison, SHA-256 manifest, timing, and resource report gates.
- Final report: SWNS -6.565 ns (within the existing -6.699 ns baseline with 0.5 ns tolerance), HWNS +0.024 ns, LUT 81.11%, BRAM9K 75%.
- A board cold-start measurement was not performed. The 3-second hardware target and exact FAT-to-display end-to-end behavior remain unverified on the board; do not claim they have been met until that measurement is made.

## Risky Files

- `rtl/sd/bmp_read_g.v`
- `rtl/sd/sd_card_bmp_g.v`
- `rtl/top/top_tf_hdmi_audio.v`
- `td_prj/av_media.al`
- `td_prj/av_media_Runs/syn_1/av_media.prj`
- `td_prj/av_media_Runs/phy_1/av_media.prj`
- `scripts/regression.sh`
