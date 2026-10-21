# Design: FAT32 indexed BMP startup

## Boundaries

- Add a FAT32 root-directory indexer and a logical-file-sector mapper under `rtl/sd/`.
- Keep `bmp_read_g` responsible for BMP header validation, row padding/orientation, RGB conversion, and pixel writes. Its load-side sector address becomes a file-relative sector index in FAT mode.
- Extend `sd_card_bmp_g` to retain each image's first cluster and directory file size, select the active file metadata, and arbitrate physical SD transactions between the filesystem indexer and BMP loader.
- Gate the existing WAV scan kick with the first committed `display_valid` state.
- Register new RTL in the canonical TD project only; refresh both generated TD run snapshots from that project before compile.

## Data Flow

1. After SD init, the indexer reads LBA 0 and selects a valid FAT32 BPB either at LBA 0 or at a supported MBR partition start.
2. It validates 512-byte sectors, cluster geometry, FAT span, total-sector arithmetic, root cluster, and maximum cluster.
3. It walks every sector in the FAT32 root directory and follows the root directory's FAT chain as needed. Each valid regular `.BMP` entry records first cluster and file size, up to the configured target.
4. After indexing completes, the existing playback controller selects an image. `bmp_read_g` requests logical file sectors in order; the mapper translates each request to a physical data LBA and reads a FAT entry only when crossing a cluster boundary.
5. The existing BMP parser and display-buffer commit handshake remain the authority for frame validity. WAV scanning starts after the first successful commit.

## Contracts and Failure Handling

- One physical SD transaction is active at a time. The indexer owns it during directory discovery; the mapper owns it during image loading. The owner is latched until sector completion or timeout, and data/end signals are routed only to that owner.
- Logical image reads are monotonically increasing from sector 0; the BMP header read and first pixel pass may both request logical sector 0. The mapper must support this reread without advancing the chain twice.
- Root and file cluster values are masked to FAT32's low 28 bits, checked against `[2, max_cluster]`, and limited by a traversal budget. Early EOC before the directory file size is an error; a file ending at its declared byte size does not require probing an extra FAT entry.
- Do not signal scan success for malformed BPB or SD failure. Existing bounded load retry behavior remains responsible for display recovery; invalid or partial frames are never committed.
- Root-level short-name extension matching supports non-ASCII display names through the FAT short alias. Directory recursion and LFN reconstruction are not required.

## Trade-offs and Rollback

- Root-only lookup matches the user's current card layout and avoids introducing recursive directory state in this startup change.
- The existing raw scanner can be retained behind compile-time/test-only wiring during development, but production startup must not issue its fixed-range scan.
- Roll back by restoring the new source/project-list changes from the `backup/pre-fast-first-image-20261002` tag plus the saved pre-existing-diff patch; do not restore or replace user-owned `.al` changes from an older snapshot.
