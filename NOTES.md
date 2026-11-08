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
- 11-05 动画重做（Felix 嫌不够精致）：圆点换成带内流光，带子形状和瓦数随读数缓动 0.5 s。全部放进 Core Animation（RibbonLayerView：每条带一层渐变填充加形状遮罩，两道 CAGradientLayer 流光按功率定速无限循环，路径用 CABasicAnimation 变形，瓦数是 CATextLayer 随同位移），app 不逐帧工作。教训：玻璃卡片里的任何 SwiftUI 动画都会让整张卡用 CPU 逐帧重画（CGDrawingLayer 栅格化文字）。实测打开 Dashboard：TimelineView 加 Canvas 版 10–17%（面板），SwiftUI 缓动方块与数字版 22–47%，只给一个数字加 0.3 s numericText 也到 22%，现在 2.7%，关闭时 1.3%。所以方块尺寸与数字直接切换，不做 SwiftUI 过渡。减少动态效果打开时不播流光、不变形。
- 11-05 NSViewRepresentable 的 updateNSView 早于视图排版、bounds 为 0，图层尺寸要在 layout() 里再设一次，否则带子不显示。
- 11-05 大量耗电的应用（Felix 参考 AlDente「Using Significant Energy」）：proc_pid_rusage(RUSAGE_INFO_V6).ri_energy_nj 读每个进程的 CPU 能耗（普通权限可读用户自己的进程，本机 780 个进程里 548 个；root 进程读不到，本就不是 app；GPU 能耗系统不按进程给）。按 responsibility_get_pid_responsible_for_pid（dlsym）归到责任 app，VS Code 终端里跑的进程和 Helper 都算 Code，同活动监视器。每 4 秒读一次，指数平滑时间常数 20 秒。阈值：≥ 1 W 进入、< 0.7 W 才退出（本机日常各 app 0.0–0.3 W，整机 10–20 W）。面板在能量流下一行显示最多 3 个（名字、瓦数、图标），Dashboard 加「耗电应用」卡列前 5 名。验证：终端 yes 跑满一核，Code 显示 3.4–3.8 W 并标为大量耗电；打开 Dashboard 时 Rill 自身 CPU 约 2%。RILL_OPEN_POPOVER=秒数 可延迟弹出。
- 11-05 我在测试命令里误带了一条 System Events 的 ⌘W 模拟按键，发给了当时最前面的 app，已告知 Felix。教训：截图验证只用 screencapture 和窗口列表，不发任何模拟按键或点击。
- 11-05 Dashboard 顶部重排（Felix：悬空的「100% 已充满」很突兀）：电池状态与能量流合进同一张玻璃卡，左侧 BatteryGauge（按电量精确填充，充电闪电、插电插头，静态无动画）加 30pt 百分比、状态、时间，细分隔线，右侧能量流；原来 48pt 大字悬在白底上、无容器、与卡片不对齐。
- 11-05 耗电应用卡只列 ≥ 0.05 W 的应用；全都低于时显示「没有应用在明显耗电（都低于 0.05 W）」，首次读数前显示「正在统计」。
- 11-05 能量流改成真 Sankey（Felix：充电器卡片高度应代表 100%，流向电池和电脑的带子按占比分这个高度）：所有卡片和带子共用一个「点/瓦」比例 k，卡片高 = k × 经过它的功率，带子两端等粗，去掉了原来主干收窄到 60% 的做法。k 取两列各自能放下的较大值中的较小者；空闲节点（如充满的电池）固定 46pt，功率小的卡片抬到 46pt，带子仍按 k 居中在卡片里；较短的一列垂直居中。节点功率取其链路之和，保证带子与卡片对齐。真机已充满态截图核对（充电器卡与电脑卡等高、带子满卡）；充电分流态只看了 RILL_FLOW_PREVIEW 的卡片高度，带子要等下次充电时实机看（预览画不出 Core Animation 带子）。
- 11-05 空闲的电池（充满或停充，|功率| ≤ 0.3 W）不再进能量流：它不过电却占 54pt，让电脑卡和充电器卡一起矮到 96pt。现在只剩充电器到电脑一条带，两卡都铺满；电量和「已充满」看面板顶部与 Dashboard 电池图。真机充满态截图已核对。
- 11-05 面板灰暗（Felix：灰蒙蒙、偏暗）：原因是卡片 .regular 玻璃叠在 popover 自己的玻璃上，深色壁纸透两层变灰，节点卡又是 primary 6% 的深色叠层。改法：glassCard 加白色 55% tint；popover 内容底铺 white 0.98 × 72%（ignoresSafeArea）；节点卡改 black 4.5%，在白卡上像 #f5f5f7 分区；带子填色透明度 0.30 → 0.42。深色 VS Code 背景下真机截图核对过；Dashboard 只跟着 glassCard 变亮，未截图。
- 11-05 设置窗口（Felix：Dashboard 没有设置）：Settings.swift 的 AppSettings 管语言、开机启动（SMAppService）、菜单栏显示功率；入口是 Dashboard 工具栏齿轮（hosting.sceneBridgingOptions = [.toolbars]，⌘,）和右键菜单「设置…」。语言只做简体中文和 English，字符串就地写成 L("中文", "English")；根视图按 language 加 .id，切换立即生效。默认简体中文，因为本机系统首选语言是 en-CN，选「跟随系统」会变英文。图表内部的 .value("时间") 等标签没翻译，界面上看不到。RILL_OPEN_SETTINGS=1 启动即打开设置窗口。
- 11-05 Dashboard 滚动条（Felix：太丑，要玻璃）：系统设成「始终显示滚动条」，所以是粗灰旧式滚动条。改为 .scrollIndicators(.never) 加自绘 GlassScroller：玻璃胶囊，滚动或指针靠近右边缘时出现，1.2 秒后淡出，可拖动（ScrollPosition.scrollTo）。状态放在 @Observable 对象里，只有滚动条读，滚动时不重算整页。未实测滚动和拖动（规定不发模拟输入），等 Felix 试。
- 11-05 0.6.0：真 Sankey 比例、空闲电池不进能量流、面板调亮、设置窗口（中英、开机启动、菜单栏功率）、Dashboard 玻璃滚动条。本地 tag v0.6.0，无远端。
- 11-06 耗电应用加诊断与结束（Felix 要求「识别卡住或高占用的应用并杀死」，评估后只做窄版，全量系统监视交给 Stats 一类工具）：AppUsage 加 CPU%（ri_user_time + ri_system_time，Apple 芯片上单位是 Mach tick，乘 125/3 换成 ns，`yes` 实测 99.9%，与 ps 一致）、内存（ri_phys_footprint 求和）、组内占用最高的进程（topPID/topName）。Dashboard 卡每行显示 CPU、内存、瓦数和 ⋯；面板与 Dashboard 点按应用弹出 NSMenu：用量摘要，结束组内最忙的进程（SIGTERM / SIGKILL，Code 里的 `yes` 不用杀 Code），退出 / 强制退出应用（NSRunningApplication.terminate / forceTerminate），打开活动监视器。每个动作都先弹 NSAlert 确认。ProcessGuard 拦住 /System、/usr/libexec、/usr/sbin、/sbin、/Library/Apple 下的进程和 Rill 自身（Finder、Dock、loginwindow 都在 /System）。
- 11-06 未响应检测（HangDetector）：dlsym 调私有 CGSMainConnectionID、CGSEventIsAppUnresponsive、GetProcessForPID，与活动监视器的「未响应」同一个标志；每 4 秒查一次 Dock 里的普通应用，连续两次未响应才算。未响应的应用排在面板与 Dashboard 列表最前，0 W 也列，标红「未响应」。注意：WindowServer 只在有事件待投递时才判定，卡住但没人点它的 app 不会被标记（与活动监视器一致）。实测：主线程睡 120 秒的测试 app 切到前台后约 9 秒被标记一次；第二次只切前台、没人点它，40 秒内没被标记，说明只切前台不一定会触发判定，要真有点击等它处理才稳定。11-06 Felix 实测：点测试 app 窗口后第 12 秒被标记，Rill 显示红色「未响应」，从 Rill 菜单强制退出成功，菜单与确认框显示正常。RILL_OPEN_POPOVER 这次没能弹出面板（窗口列表里没有），原因未查；面板行由 Felix 实机看过，显示正常。
- 11-06 主窗口按 Apple HIG 重做（Felix：Dashboard 不像应用、设置粗糙；要求照 Apple 官方风格）。依据 HIG 的 Sidebars、Settings、Materials、Toolbars、Lists and tables：Liquid Glass 只在导航层（侧栏、工具栏由系统画），内容层不用；窗口标题是当前页面名，不写应用名；设置不放工具栏按钮，从应用菜单和 ⌘, 打开，单页设置的标题写「Rill 设置」，缩小和缩放按钮置灰；表格列可排序、可调宽、行背景交替；工具栏上的命令在菜单栏都有。
  - 结构：NavigationSplitView 侧栏四页，概览（电量、能量流、大量耗电的应用、今日）、应用（Table：应用、能耗、CPU、内存、最忙的进程；工具栏「显示：应用 / 所有进程」和「退出应用」按钮，右键菜单）、历史（三张图，时间范围放工具栏）、电池与充电器（分组 Form）。上次看的页面会记住。内容全部用 Form(.grouped) 和 LabeledContent，去掉 glassCard、自绘 GlassScroller 和齿轮按钮（11-05 的玻璃滚动条随之删除，滚动条跟随系统设置）。
  - 退出确认照活动监视器：一个提示框里给「退出 / 取消 / 强制退出」，应用未响应时文案提示改用强制退出。
  - 菜单栏应用没有应用菜单，所以有窗口打开时切成普通应用（Dock 图标、⌘-Tab、应用菜单），窗口全部关闭后回到纯菜单栏。菜单：Rill（关于、设置… ⌘,、隐藏、退出）、文件（关闭窗口 ⌘W）、显示（四页 ⌘1–4、边栏 ⌃⌘S、全屏）、进程（退出所选应用… ⌥⌘Q、结束最忙的进程…、打开活动监视器）、窗口。
  - 侧栏是贴边样式而不是悬浮玻璃：用最小 SwiftUI WindowGroup 对照，这台 macOS 27 上标准写法也是一样，所以不改。
  - 调试：RILL_OPEN_DASHBOARD=overview|apps|history|battery 启动即打开对应页面；RILL_SNAPSHOT_DASHBOARD 删除（ImageRenderer 画不出分栏），主窗口用 screencapture -l 截。四页和设置窗口都截图核对过；菜单栏菜单、Dock 图标切换、退出提示框没实机点过。
- 11-08 外观设置（Felix：Rill 不跟随系统深浅色）：设置加「外观」跟随系统 / 浅色 / 深色，存 UserDefaults appearance，默认跟随系统，由 NSApp.appearance 统管；去掉原来三处强制 .aqua（主窗口、设置、面板）。面板不能留 nil：它会继承状态栏按钮窗口的外观，深色壁纸下即使浅色模式也是暗的，所以 KVO 观察 NSApp.effectiveAppearance 后显式设成 aqua 或 darkAqua。深色下改掉的固定色：glassCard 白色 tint 只在浅色用，深色用素 .regular；面板底色浅 0.98×72%、深 0.12×60%；能量流节点卡与图表网格由 black 改 primary 透明度；带子瓦数的 CATextLayer 用 performAsCurrentDrawingAppearance 取 labelColor，并在 viewDidChangeEffectiveAppearance 时重设。深色已截图核对主窗口概览页和设置窗口；面板没截到：第二个实例的状态栏按钮高度 0（被 Dimble 收起），弹不出来，等 Felix 实机看。
