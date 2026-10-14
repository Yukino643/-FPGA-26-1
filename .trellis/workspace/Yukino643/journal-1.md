# Journal - Yukino643 (Part 1)

> AI development session journal
> Started: 2026-10-02

---

## 2026-10-02 - First image startup optimization

- Replaced raw sector-signature scanning with FAT32 root-directory BMP indexing and fragmented-file sector mapping.
- Delayed WAV scanning until `display_valid`; surfaced filesystem scan errors through the board diagnostic status.
- Pipelined BPB geometry validation after TD timing identified its arithmetic chain as the new critical path.
- Moved the status seven-segment scanner onto `sd_card_clk` (100 MHz) and adjusted its divider to retain 200 Hz per digit, removing a cross-domain hold violation.
- `bash scripts/regression.sh`: 35/35 passed. `bash scripts/regression.sh --full`: 36/36 passed.
- Final reports: SWNS -6.565 ns, HWNS +0.024 ns, LUT 81.11%, BRAM9K 75%. The existing setup path still has negative slack but passes the repository baseline tolerance.
- Board cold-start timing and a FAT32-to-HDMI end-to-end 3-second measurement remain pending.



## Session 1: 连续PCM曲线与无黑场双页转场

**Date**: 2026-10-03
**Task**: 连续PCM曲线与无黑场双页转场
**Branch**: `fix/bmp-header-spi-valid`

### Summary

连续插值曲线；默认16px双页横推；可选双页交叉淡化。当前源码全量构建通过，bit/manifest一致，分支与修改前恢复点已上传。

### Main Changes

- 沿用老师第十二讲采集契约和第十讲双页混合；页交接保持目标B一整帧。

### Git Commits

| Hash | Message |
|------|---------|
| `bcece2b` | (see git log) |

### Testing

- [OK] 基础40/40、完整41/41、独立报告fails=0；默认16px整链路101帧517120像素。

### Status

[OK] **Completed**

### Next Steps

- 下载2026-10-03 01:45:46生成的新bit，检查曲线、接缝、末帧、连续按键、音频及应急；setup仍负余量。


## Session 2: 圆润PCM波形与KEY2事务隔离

**Date**: 2026-10-03
**Task**: 圆润PCM波形与KEY2事务隔离
**Branch**: `fix/bmp-header-spi-valid`

### Summary

真实PCM的B样条与逐帧平滑；255积压请求、双成功提交及源写握手隔离；基础44/44，全量45/45，报告fails=0，bit和备份tag已推送。setup未全闭合，板测待用户下载。

### Main Changes

- 保留老师双bank完整组发布，消隐流水生成同步BRAM曲线
- 隔离失败源和旧完成，成功同拍锁显示pending；修复请求恢复、半字清理及短尾写入

### Git Commits

| Hash | Message |
|------|---------|
| `a75b408` | (see git log) |

### Testing

- [OK] basic44/full45/独立报告0失败；678次切换、20消抖按键模型、11成功0失败提交、3次全目标缩放

### Status

[OK] **Completed**

### Next Steps

- 板级检查波形圆润/时间平滑、KEY2逐次40次及转场中连按5次、两路HDMI和应急


## Session 3: HDMI-B 720p verified implementation

**Date**: 2026-10-13
**Task**: HDMI-B 720p verified implementation
**Branch**: `feat/hdmi-b-720p`

### Summary

HDMI-B 1280x720/60; RGB565 two pages, teacher frame ownership/blend/waveform; basic51/full52/report0; board pending

### Git Commits

| Hash | Message |
|------|---------|
| `fa1e485` | (see git log) |

### Testing

- [OK] 50 source checks; 6451200 pixels no underflow; 41 switches; audio2400 ticks; current-source TD

### Status

[OK] **Completed**

### Next Steps

- Board HDMI-B seven BMP/WAV, KEY2 repeat, cold-start and long stability


## Session 4: KEY2 next-frame prefetch and resource audit

**Date**: 2026-10-14
**Task**: KEY2 next-frame prefetch and resource audit
**Branch**: `feat/key2-next-prefetch`

### Summary

Recovered interrupted build, verified prefetch ownership and real memory-write checks, completed current-source TD and resources; GitHub upload pending network.

### Main Changes

- Prefetch next 720p image in idle page; teacher complete-page/frame-boundary rules retained.

### Git Commits

| Hash | Message |
|------|---------|
| `52cd68f` | (see git log) |

### Testing

- [OK] Source 52/52, basic 53/53, filtered full build 53/53 plus independent full display 6451200 pixels; reports 0 failures.
- [OK] Poisoned target page and real write interface count/mask check passed; disabled memory write negative test rejected.

### Status

[OK] **Completed**

### Next Steps

- Board-test hot/cold KEY2, continuous key presses, WAV and long-run prefetch.
- Push feat/key2-next-prefetch when GitHub TCP 443 or existing local proxy becomes available.
