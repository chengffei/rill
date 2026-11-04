# Joule NOTES

自用菜单栏工具：实时充放电功率与能量流。2026-11-04 建，不开源、不发版，不占 WIP。

## 现状
- 0.1.0：菜单栏显示瓦数（插电显示输入功率，用电池显示放电功率）；左键面板（能量流、近 10 分钟曲线、充电器与电池读数），右键菜单（开机启动、退出）。
- 数据全部来自 AppleSmartBattery 注册表，普通权限可读：PowerTelemetryData 的 SystemPowerIn、SystemLoad、AdapterEfficiencyLoss、SystemVoltageIn、SystemCurrentIn；电池功率 = Voltage × InstantAmperage；AdapterDetails 给充电器名、额定与协商电压电流。
- macOS 27 注册表里没有电池温度，第一版不显示。要做就走 SMC 读 TB0T（读不受 27 的写封锁影响），未验证。

## 命令
- `scripts/bundle.sh --install`：release 构建、签名、装进 /Applications 并启动。
- `swift test`：解析与历史窗口测试（需 Xcode 工具链，脚本已设 DEVELOPER_DIR）。
- `JOULE_SNAPSHOT=/path.png .build/release/JouleApp`：7 秒后把面板渲染成 PNG 并退出。
- `JOULE_DEBUG=1`：2 秒后打印状态栏按钮窗口 frame。

## 记录
- 11-04 首次装好后菜单栏看不到图标：JOULE_DEBUG 显示按钮窗口高度 0，被系统或 Dimble 收起。需要在 Dimble 或「系统设置 → 菜单栏」里放出来。
