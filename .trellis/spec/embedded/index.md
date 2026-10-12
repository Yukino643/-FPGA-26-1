# FPGA video guidelines

## Pre-development checklist
- Read the relevant teacher example before adapting display features.
- For continuous curves or seamless transitions, read [continuous-display.md](continuous-display.md).
- For the HDMI-B 720p branch, read [hdmi-b-720p.md](hdmi-b-720p.md); its pixel packing and native Windows gates supersede the legacy 640 path.
- Keep RGB, coordinates and DE at the same pipeline phase.
- Identify source and destination clocks for every handshake.

## Quality check
- Frame page ownership changes only during vertical blanking after all scaler writes finish.
- Commit payload must be registered before its event is consumed.
- Alpha arithmetic uses saturation; no 8-bit wrap at full scale.
- A frame restart has priority over issuing any command with the old page address.
- PCM display and capture banks remain separate; only complete captures can be published.
- Keep sample cadence separate from payload validity: HDMI may emit a timed silent sample while its PCM FIFO is empty, but waveform capture must advance only on a real FIFO dequeue or another source's real sample-valid pulse.
- For single-framebuffer fades, change alpha only at frame boundaries, switch pages at full black, and retain the blank/prefetch interval before fading the new page in.
- A horizontal push must change the source address as well as the seam: both pages read each row from the same scroll offset, wrap within that row, and advance the row only after 640 output words. Limit bursts at source, output and frame boundaries.
- For seamless dual-page transitions, keep both pages read-only until completion. After changing A to the target page, display B for one full prefetched frame before handing back to A and releasing the loader.
- Render a continuous PCM curve with signed interpolation and connect the current and following pixel columns, including steep slopes. Clamp the last sample and out-of-window indices; keep RGB/DE/coordinates in the same phase.
- Run actual-top pipeline simulations, regression.sh and regression.sh --full; validate source/bit manifest.

- Precompute costly curve arithmetic in vertical blanking; use explicit single-write BRAM and preserve pixel latency. Check real resource inference in TD.
- Latch both transaction completion events independently, including same-cycle events. Clear both on start, commit or error; errors never publish a partial page.
- Pending key requests saturate and are consumed one by one; keep image modulo indexing separate. A new manual action must be able to retry an all-failed image set.
- Clear partial packed pixels on abort/new frame; a final partial write burst must terminate using its actual length.
- Start scaler only after a fresh source write request/ACK boundary and both source-success/write-finish events. Cancel on restart/error, ignore old completion events, and preserve CDC toggle history across SD deinit.
