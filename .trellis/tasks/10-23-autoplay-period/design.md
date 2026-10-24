# 设计

根因：sd_card_bmp_g的预取计时条件包含!hold_load，顶层hold_load又包含resize_busy，因此缩放/转场反复清零。计时从显示提交重新开始，覆盖全部工作；到期锁存单条请求并停止累加，实际发布仍受prefetch_ready与hold_load保护。修改周期、自动开关、任意实际提交清零计数及自动待请求，周期比较用>=。两位周期设置同SD域，无新CDC。默认PREFETCH_NEXT=0保留历史加载调度。

参考：本机老师完赛工程rtl/control/media_player_control.v的busy计数与配置复位；官方例程SD/sd_card_bmp.v的空闲计数。借鉴配置重启和有界请求，但不照搬忙时清零。用户同意最小2秒，采用2/3/5/10秒；慢卡未就绪仍延后，不能以丢弃页面完整性换准点。

首次完整P&R暴露既有FAT32数据LBA路径的减法、动态移位、双加法串联，SD域setup为-0.228ns。复用sector_lba寄存器分开运算，增加三个SD周期（100MHz下30ns/数据扇区），仅最终地址稳定后发sector_req；请求握手、文件边界与错误逻辑保持。首次失败报告保存在build/720p/autoplay-period/first-build-sd-fail，不作为发布证据。

拆拍后seed17在route/hold缓冲增量布线遇到PHY-8023冲突，日志保存在second-build-route-fail。按TD官方place seed接口使用工程历史采用过的seed13，保留LogicLevelOptimize、hfn_opt_effort high、route effort routability及全部时序/资源门限；不是重复同一失败命令碰运气。

seed13的SD/video余量+0.291/+0.541ns，但ext_mem两条长连线setup最低-0.143ns，未发布；报告保存在third-build-ext-fail。继续使用官方seed14调整布局，不扩大FIFO/SDRAM功能改动。
