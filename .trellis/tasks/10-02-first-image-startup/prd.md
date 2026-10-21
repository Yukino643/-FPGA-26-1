# First image startup optimization

## Goal

Show a complete first BMP from the FAT32 TF card within 3 seconds after SD initialization, without scanning arbitrary card sectors for `BM` signatures.

## Background and Requirements

- The active design scans raw sectors from LBA 0 through LBA 131071 and waits for the scan to finish before loading the first image. This is the dominant cold-start delay.
- The WAV scanner starts automatically after SD initialization and competes with BMP reads for the single SD controller.
- Keep the current BMP pixel decoder, SDRAM/scaler pipeline, frame commit handshake, HDMI path, and playback controls.
- Discover up to 8 regular BMP files from the FAT32 root directory by `.BMP` extension, independent of the generated 8.3 base name. Follow the root-directory cluster chain.
- Read image bytes using the FAT32 file cluster chain so fragmented files work. Support MBR FAT32 partition types `0x0B`/`0x0C` and a FAT32 superfloppy volume; require 512-byte sectors and validate BPB arithmetic and cluster bounds.
- Keep failures bounded and visible through the existing load/error status path. An absent or corrupt BMP must not hang startup or commit an incomplete frame.
- Start WAV scanning only after the first image has been committed to the display buffer.

## Out of Scope

- FAT16/exFAT, nested directory recursion, LFN text decoding, file writes, JPEG/PNG decoding, and changes to the display/scaler architecture.
- A claim of board-measured 3-second startup without an on-board cold-start measurement. Simulation and build results must report the measured transfer/cycle budget and distinguish it from hardware timing.

## Acceptance Criteria

- [ ] FAT32 scan reads only MBR/BPB, root-directory sectors, and necessary FAT sectors; it does not walk a fixed raw LBA range.
- [ ] Any root-level BMP short-name alias is recognized by extension; directories, deleted entries, LFN entries, volume labels, and non-BMP files are ignored.
- [ ] FAT32 root-directory and BMP file cluster chains can be fragmented; each next-cluster read is range-checked and bounded against loops/invalid EOC.
- [ ] A fragmented 640x480x24 BMP is decoded exactly through the existing source-frame/scaler/display commit path.
- [ ] Missing BMP, malformed BPB, bad directory entry, invalid cluster, early EOC, SD timeout, and no-WAV conditions terminate without an incomplete frame or infinite scan.
- [ ] WAV scanning does not issue SD requests before `display_valid` is asserted.
- [ ] `bash scripts/regression.sh` passes; then `bash scripts/regression.sh --full` passes with report checks confirming the bit manifest, TD snapshots, and project entry all match current source.
- [ ] Existing working-tree changes remain intact; the pre-change HEAD and pre-existing tracked diff are recoverable from the backup tag and patch file.
