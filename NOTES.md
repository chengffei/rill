# Rill NOTES

11-04 由 Joule 改名为 Rill（小溪），目录 personal/rill，Bundle ID io.github.chengffei.rill。

自用菜单栏工具：实时充放电功率与能量流。2026-11-04 建，不开源、不发版，不占 WIP。

## 现状
- 0.1.0：菜单栏显示瓦数（插电显示输入功率，用电池显示放电功率）；左键面板（能量流、近 10 分钟曲线、充电器与电池读数），右键菜单（开机启动、退出）。
- 数据全部来自 AppleSmartBattery 注册表，普通权限可读：PowerTelemetryData 的 SystemPowerIn、SystemLoad、AdapterEfficiencyLoss、SystemVoltageIn、SystemCurrentIn；电池功率 = Voltage × InstantAmperage；AdapterDetails 给充电器名、额定与协商电压电流。
- 0.2 起功率走 SMC：PDTR 充电器输入、PSTR 整机负载、B0AV×B0AC 电池功率（B0AC 充电为正）、TB0T 温度，每 2 秒一次；电量百分比、充电器信息、容量仍读注册表，10 秒缓存。读不到 SMC 时退回注册表。

- 0.3 Dashboard 窗口：面板底部「打开 Dashboard」、右键菜单、Finder 或 Spotlight 再次打开 Rill 都会打开它。内容：电量与能量流、电池、充电器、今日用电四块，功率曲线（1 小时、6 小时、24 小时、7 天，悬停看读数），电量与温度曲线。
- 历史：每分钟一条均值写 `~/Library/Application Support/Rill/history/日期.jsonl`，保留 30 天，启动时载入 7 天。曲线超过 360 点按时间桶平均。今日用电按每条记录覆盖的秒数加权。

## 命令
- `scripts/bundle.sh --install`：release 构建、签名、装进 /Applications 并启动。
- `swift test`：解析与历史窗口测试（需 Xcode 工具链，脚本已设 DEVELOPER_DIR）。
- `RILL_SNAPSHOT=/path.png .build/release/RillApp`：7 秒后把面板渲染成 PNG 并退出；加 `RILL_SNAPSHOT_DASHBOARD=1` 渲染 Dashboard（不带滚动，分段控件画成黄条是渲染器限制）。
- `RILL_HISTORY_DIR=目录`：历史改存到这个目录，调试用，别和正在运行的 Rill 共用真实目录。
- `RILL_DEBUG=1`：2 秒后打印状态栏按钮窗口 frame；菜单栏每次变化打印读数。
- `RILL_SMC_DUMP=/path.txt swift test --filter SMCDiscovery`：列出 P、B、D、TB 开头的 SMC 键及 4 秒内是否变化。
- `RILL_SMC_CAL=/path.txt swift test --filter SMCCalibration`：逐秒采 130 秒，与注册表每分钟的值对比。

## 记录
- 11-04 首次装好后菜单栏看不到图标：RILL_DEBUG 显示按钮窗口高度 0，被系统或 Dimble 收起。需要在 Dimble 或「系统设置 → 菜单栏」里放出来。
- 11-04 图标：深蓝底上三条电路走线像小溪蜿蜒，上下两条支流走线经节点汇入，线上白点是电流。design/make_icon.py 生成 appIcon.svg，scripts/generate-icon.sh 转 Resources/AppIcon.icns。CoreSVG（sips）渲染时，带 stroke-opacity 的粗线会在拐点叠出暗斑，所以河床用实色。
- 11-04 注册表 PowerTelemetryData 每 60 秒才更新一次（实测 UpdateTime 间隔 60 s），且是瞬时值不是平均，2 秒轮询等于 1 分钟一跳。改读 SMC。
- 11-04 SMC 字节序：Apple 芯片上 flt 与 ui16、si16、ui32 都是小端（B0AV 原始 0x31C9 → 12745 mV，与注册表 12757 对上）；#KEY 计数是大端。
- 11-04 PDTR 与 PSTR 响应速度不同，负载变化时 PSTR 可比 PDTR 高 4 W；60 秒均值二者相差 0.02 W。PowerModel 对输入、负载、电流取相邻两次平均，插拔时不平均。
- 11-04 性能：后台平均 CPU 约 1.0%（注册表版约 0.9–1.7%），内存 17 MB。4 秒抽样里 SMC 读取约 2 ms，主要开销是菜单栏重画；面板关闭时不推送界面数据，菜单栏文字不变不重画，图标不变不重设。想再省可把菜单栏改成整数瓦。
- 11-04 0.3.0 Dashboard。ImageRenderer 画不出 ScrollView 内容和 AppKit 分段控件，截图用 scrolls: false；真实窗口用 screencapture -l 窗口号核对过。温度图不填色，否则面积图把 y 轴拉到 0。
- 11-04 菜单栏主体改为自绘电池图形（BatteryGlyph：外框加按电量填充，充电显示闪电，插电保持显示插头，光晕只切在电池内部）；右键「在菜单栏显示实时功率」开关，存 UserDefaults showsPower，默认开。
- 11-04 菜单栏电池改为纯 SF Symbols（Felix 要求尽量用原生）：battery.0/25/50/75/100percent 按最近一档，充电用 battery.100percent.bolt。macOS 27 上这些符号不支持 variableValue，100percent 是实心整块，带闪电的只有满格一种，所以自绘填充和叠加闪电都试过后放弃；悬停提示显示精确百分比。
- 11-04 菜单栏电池第三版（Felix 嫌纯 SF Symbols 小、不精致，给了 AlDente 原生风参考）：自绘 25.5×13 外框（40% 透明）加精确填充，标记用系统 bolt.fill、powerplug.portrait.fill；镂空用 CIMorphologyMaximum 把符号均匀外扩 1.3pt（8 倍渲染）后 destinationOut，并只裁在电池内部。之前两次失败：偏移 8 次叠画会出锯齿残影；用更粗更大的符号当镂空，形状不同心会切歪。
- 11-04 Liquid Glass（Felix 要求面板和主界面符合 Apple 新玻璃风格）：最低系统提到 macOS 26（swift-tools 6.2，语言模式仍 v5）。卡片统一 glassCard()（glassEffect .regular，18pt 圆角），外层 GlassEffectContainer；面板按钮 .buttonStyle(.glass)；Dashboard 透明标题栏加 fullSizeContentView，内容顶部留 44pt 让开红绿灯。文字改语义色（primary、secondary），固定灰在玻璃上对比度不够。面板玻璃会透出桌面，深色壁纸下整体偏灰，属系统行为。截图用 RILL_OPEN_POPOVER=1 启动后 screencapture -l（ImageRenderer 画不出玻璃）。
- 11-04 面板上半部被遮挡：弹出时内容还是空数据的小尺寸，数据填入后 SwiftUI 把 popover 从底边往上撑高，窗口 Y=-260。按窗口截图（screencapture -l）会连屏幕外部分一起截，所以之前没看出来；查位置用 scratchpad 的 winwatch（打印弹出窗口的 Y 和高）。修法：hosting.sizingOptions = []，弹出前和每次更新时用 sizeThatFits(宽 360) 自己设 contentSize（fittingSize 会把图表压到最小，只有 346）；snapshot 关着也照常发布，弹出前尺寸就是对的。修后 Y=27、高 635。
- 11-05 能量流改为 Sankey（Felix 嫌旧版不如 AlDente 的分流带）：FlowGraph（RillCore，有测试）把状态拆成电源（左）、用电方（右）和链路；FlowView 用 Canvas 画带子，粗细按功率，节点少的一侧做主干收窄到 60% 居中，另一侧铺满方块；光点沿中线流动，速度随功率，经过中间文字时淡出。旧版「充电器 → 电脑 → 电池」串联画法在原理上就错（电池不经过电脑充电）。调试：RILL_FLOW_PREVIEW=/path.png 渲染四种状态。
- 11-05 电脑功率改为与注册表同一定义：插电时 = 输入 − 电池功率（注册表 SystemLoad = SystemPowerIn − BatteryPower，实测分毫不差），用电池时 = 电池放电功率；不再用 PSTR。原因：PSTR 与 PDTR 响应速度不同，充电时 14.2 + 9.3 = 23.5 W 超出 19 W 输入。转换损耗改为保留注册表 AdapterEfficiencyLoss（每分钟更新）。
