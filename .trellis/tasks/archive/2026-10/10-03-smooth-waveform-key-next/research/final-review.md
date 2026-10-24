# 最终只读审查（2026-10-03）

## 审查结论

**本次只读最终复核通过：两项P1均已关闭，当前限定范围未发现剩余阻断项。** 视频只接受成功提交，scaler只在本次源解析成功与本次源SDRAM写完均到达后启动一次。下述原问题及反例保留为历史；第三次复核给出当前启动隔离结论和验证限制。本次未修改RTL、脚本或测试，也未运行全量回归。

## 已修复的 P1：顶层视频提交绕过双完成门

| 落点 | 修复前行为 | 当时问题 |
|---|---|---|
| `rtl/top/top_tf_hdmi_audio.v:264` | `commit_sync <= {commit_sync[1:0], scaler_done_toggle}` | 视频 transition_ctrl 接到的是原始 scaler 完成，独立于 `sd_card_bmp_g` 的源解析完成/错误门 |
| `rtl/top/top_tf_hdmi_audio.v:364–368` | scaler_done 边沿设置 display_submit_pending_sd | 已成功的目标写入被提前认为是成功显示提交 |
| `rtl/sd/sd_card_bmp_g.v:452–464` | 源解析与写完成双锁存后才更新 disp_buf_idx/img_idx | 此安全门只控制 manager 的本地状态，未控制实际视频提交事件 |

### 定向证据

独立 `D:/FPGA/tmp_key_repeat_audit/tb_top_commit_order_audit.v` 引用 `scripts/extract_display_commit.py` 提取的真实顶层 CDC/transition 原文，同时实例化真实 manager。仅环境注入源解析未完成、scaler 已完成的允许顺序。

```
REPRO VIDEO_COMMIT_BEFORE_SOURCE commits=1 manager_busy=1 manager_source=0 manager_disp=0 video_target=080000
REPRO SOURCE_ERROR_RETRY_DURING_VIDEO_HOLD retry=1 hold=1
```

管理器尚未提交（display page0、busy1、source_seen0），视频已经把 page1 作为转场目标，随后源错误仍允许 manager 重启同一目标页装载。由此不能满足“错误不得提交失败页”和两页转场期间只读契约。

这个环境反例证明 RTL 边界缺陷；**未证明此次三张正常640×480卡内图片上板已发生该事件顺序**。实际 writer 按像素字数完成，BMP 必须等最后扇区结束并检查像素计数；末扇区尾部停顿/错误或文件尾部异常时，两完成的相对顺序并无接口保证。

### 已执行修正

1. `sd_card_bmp_g` 新增持久 `display_commit_toggle` 输出，只在两完成且无错误的成功提交分支翻转；复位清零。
2. 顶层 `commit_sync` 改同步此成功提交 toggle，保持 write_buf_idx/commit_buf 的稳定 payload 同步方式。
3. 顶层 `display_submit_pending_sd` 改由此成功提交事件设置，避免 scaler 完成后源失败却再没有成功视频事件可释放造成新的锁死。注意SD同域设置hold必须与manager的load_busy清零同拍生效：可导出成功判定的组合commit_pulse给顶层锁存pending，同时导出持久toggle给video；若从toggle再延后检测，必须增加立即hold条件防止下一拍先启动新装载。
4. `scaler_done_toggle` 到 manager 的 write_finish 完成路径保持；source_restart/loader retry 保持。
5. 在 manager+真实顶层 CDC 组合测试中覆盖 scaler先完成后源成功、scaler先完成后源失败、错误与完成同拍；失败不能发 commit，成功只发一次，下一次KEY2可继续处理。

## 已通过项

| 范围 | 只读结论 | 本轮重跑证据 |
|---|---|---|
| 8位请求队列 | 255积压饱和；同拍插入/消费净0；成功循环无累计次数限制 | 678次切换、20物理消抖按键PASS |
| manager双完成锁存 | 任意顺序/同拍均可提交；错误优先清除完成 | tb_image_requests三事件顺序和错误优先PASS，但只证明manager本地门 |
| 全坏图手动恢复 | 全部失败后自动请求不清屏蔽；新物理按键可开启有界重试 | tb_image_requests PASS |
| 候选回退 | 唯一好图位于2不再回退坏图0 | tb_image_requests PASS |
| 源打包 frame_restart | error或load_start优先清残留半字、行计数和输出valid；top已连接 | tb_src_packer全部6组PASS |
| 源写短尾 | burst_limit=min(remaining,BURST_SIZE)，按实际字数记账，结束可接下一事务 | 1/16/17/31/129字、地址核对与读占用停顿PASS |
| PCM真实采集 | 真实valid、跨帧采集、32点双bank、完整组VS发布保持 | tb_audio_waveform PASS |
| B样条及时间平滑 | Q4节点每VS误差1/4收敛；消隐Horner流水；列范围/陡坡连通/末点检查 | 32/512/640列，共5920列PASS |
| 同步查表与top相位 | 模块一拍同步读替代waveform_q，RGB/DE/坐标仍共四拍 | 实际top管线1280像素、2行PASS |
| 显式BRAM production/SIM | 单写端口；相同同步读一拍；production的NOREG连接与既有afifo/scaler/wav一致 | 活动显示前表完成，写读碰撞仅在消隐期且输出不可见；行为模型未证明真实物理IP |
| 回归脚本 | waveform/video_pipeline均加SIMULATION；image_requests指定顶层避免未例化顶层被自动运行；新测试纳入回归 | 脚本已读；全量门由主任务继续 |
| 源码格式 | RTL/脚本/现有测试 diff --check无错误 | 重跑退出0 |

## 构建与板级边界

现读TD报告LUT15707（80.14%）、BRAM9K49（76.56%）；主任务反馈最新构建 SWNS=-6.565ns、HWNS=+0.022ns、报告fails0。全量/清单最终结果仍需主任务确认。不能称setup全闭合。

板级仍需检查真实TF末扇区完成/错误恢复、快速连续KEY2、转场末尾是否重现上一页、曲线移动观感。该审查没有代替用户上板验收。


## 第二次复核（成功提交门修正后）

| 项目 | 当前结论 |
|---|---|
| 无下一拍装载窗口 | display_commit_pulse由当前load_busy和两完成组合给出；manager清busy和top设pending在同一posedge，下一拍manual_next_start被hold阻止 |
| CDC payload | write_buf_idx在装载开始确定，成功前已稳定；pending保证到视频release前不改，事件3级toggle与payload2级同步保留 |
| 复位toggle | rst_sd清0；!sd_init_done与重新扫描不清事件toggle，因此单独SD重新初始化不会产生下降沿伪事件；全局rst_video同步清commit_sync |
| 失败提交 | 当前源码的错误同拍成功pulse为0；manager错误清两个seen；旧的直接scaler→video通路已移除 |
| 重新运行 | TB_TOP_COMMIT_ORDER PASS success_commits=11 failed_commits=0 retries=2；TB_DISPLAY_COMMIT PASS commits=8 |

### 已关闭历史项 [P1] 旧scaler的迟到完成事件被重试继承

修复前错误分支立即置load_start_pulse，load_busy仍为1；write_finish_seen清零只清已经到达的完成，既没有终止旧scaler，也没有事务ID。若错误前像素已经写齐而末扇区结束/校验出错，frame_writer已经触发旧scaler（top的scaler_start_tgl仍直接由frame_write_finish_pulse翻转），错误后开始读重试图，旧scaler晚到的done_toggle被管理器当作新重试的完成。新源load_done随后到达即可提交，尽管重试本轮scaler尚未完成/甚至没有启动。

独立反例 `D:/FPGA/tmp_key_repeat_audit/tb_late_retry_completion_audit.v` 引用真实top CDC并实例化真实manager：错误→load_start重试→旧scaler完成→新source_done，没有新scaler完成。

```
REPRO OLD_SCALER_EVENT_COMPLETES_RETRY commits=1 new_scaler_events=0 busy=0
```

这说明“错误清锁存不继承旧完成”只对错误前或同拍的旧事件成立，错误后的旧事件仍未隔离。现有top_commit_order两个retry只覆盖旧写完成已到达或同拍，没有覆盖迟到旧完成。

最小稳妥方向：把scaler启动改成“本次源解析成功且本次源SDRAM写完”双门，不允许失败源事务启动scaler。在SD域保存两完成标志，清/重新arm点使用新源write_req/write_req_ack握手（不是只有load_start脉冲），防止旧sourcewriter完成在重试头读取阶段迟到被继承；error/deinit撤销本轮arm。所有source_done后不再可能继续产生本轮源解析error，故失败尝试不会遗留在跑scaler。另一可选方向是完整pipeline事务ID/cancel，但改动更大。

需增加实际启动链集成测试：旧sourcewriter/旧scaler迟到完成不能发新成功toggle；失败尝试不启动scaler；新write_ack之后只使用本事务完成事件。此反例仍不能证明本次用户三张640x480板测故障已经发生该路径。


## 第三次复核（source_scaler_gate与真实顶层启动链）

### 当前结论：第二项P1已关闭

| 检查对象 | 当前源码证据 | 结论 |
|---|---|---|
| scaler启动来源 | top的scaler_start_tgl仅由u_source_scaler_gate输出，不再由原始frame_write_finish_pulse直接翻转 | 失败源尝试无法启动缩放 |
| 事务重新使能 | source_restart/deinit清seen并进入WAIT_REARM；等write_req低且ACK同步链全部低，再锁存新req并等待新同步ACK上升 | 头部阶段旧源writer完成不能继承 |
| ACK CDC | top source_write_ack_sync_sd两级同步给BMP；gate原始ACK经过ack_meta/ack_sync相同两级同步；req_seen容许request先撤销 | 解析器与gate接受边界对齐，不因gate延后同步丢ACK |
| 源双完成 | 新ACK后source_done/frame_write_finish分别sticky；任意先后或同拍齐才翻转一次；S_DONE忽略重复完成 | 已齐像素但解析失败的尝试不启动scaler，不产生迟到旧scaler任务 |
| 错误优先 | error组合进入source_restart；source_restart优先于握手与完成；重试/新装载重新读BMP头 | 错误与源完成同拍零启动 |
| toggle历史 | rst清0，deinit/restart只撤销事务不改toggle | SD重初始化不制造scaler CDC下降沿伪启动 |
| 顶层页payload | 成功前manager保持busy，write_buf_idx与尺寸稳定；scaler完后成功pulse同步锁pending，视频release再允许新装载 | 无下一拍装载抢先窗口，成功页payload稳定 |
| 当前联合测试 | tb_top_commit_order包括真实gate实例（reg_source_scaler_gate.vh由top提取）+真实manager+真实topCDC | 不再允许孤立环境注入“失败源仍能启动scaler”作为合法pipeline行为 |

### 当前证据与复核边界

- 独立gate定向测试此前在本次实现后运行：`TB_SOURCE_SCALER_GATE PASS starts=7 orders=3 stale_finish=blocked delayed_ack=accepted ack_same_cycle=accepted deinit=stable`。
- 当前主代理定向验证结果：`TB_TOP_COMMIT_ORDER PASS success_commits=11 failed_commits=0 retries=2 stale_writer=blocked scaler_starts=11`。本次只读核对测试源码和提取脚本，覆盖源写先到但解析未成功零启动、错误尝试零启动、重试头部旧writer完成丢弃、错误与双完成同拍、后续8次转场。
- 主代理当前top_scaler验证三次完整640×480目标缩放，分别源640×480/page0、320×240/page1、640×480/page0。当前源码确实实例化实际gate并给出真实新req/ack与两源完成；本次未重复运行耗时测试。
- 旧`tb_late_retry_completion_audit`直接注入失败尝试的scaler_done，绕过新启动门，只能作为修复前反例；不能用它宣称当前真实启动链仍有同一问题。失败尝试无scaler启动，而新事务只接受本次源写握手后的两完成，是本次关闭P1的关键。
- WAIT_REARM要求restart后至少有write_req=0的空闲拍。实际bmp_read_g重新读文件头及32拍头校验在ST_LOAD_WAIT请求前提供此间隔；不支持把restart与一个从不撤销的全新write_req强行绑在同拍。
- 复核基于本工程顺序装载与“源成功后不再产生同一源事务load_error”的协议；行为模型不验证物理SD接口、亚稳概率或SDRAM刷新电气时序。突发断卡/控制器重初始化等恢复观感仍需板级复测。
- 当前TD构建及最终manifest/报告门继续由主任务收取，本审查没有用旧bit作为通过证据。仍须记录setup负余量，不能称时序全闭合。
