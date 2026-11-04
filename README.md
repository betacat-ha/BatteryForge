# 电池锻炉（BatteryForge）

[English](README_EN.md)

电池锻炉是一款使用 SwiftUI 构建的 macOS 电池循环与负载测试工具。它可以读取电池状态，按照设定的上下限自动切换充电与放电，并在放电阶段运行可选的 CPU 与 GPU 高负载任务。

> [!WARNING]
> 本项目会通过特权后台服务直接控制受支持 Mac 的 SMC 充电相关键，并可持续制造高负载。该功能可能增加电池循环次数、温度和硬件损耗。请在理解风险后使用，并确保设备散热良好。不同机型和系统版本的支持情况可能不同。

## 功能

- 读取电量、电压、电流、功率、温度、循环次数和剩余时间。
- 显示设计容量、最大容量、计算所得电池健康度以及系统报告的电池健康值。
- 低于下限时恢复充电，高于上限时停止充电并切换为电池供电。
- 放电阶段可同时运行多线程 CPU 和 Metal GPU 负载。
- 循环由特权 helper 持续执行，关闭主窗口或退出 App 后仍可运行。
- 整个循环期间阻止空闲睡眠，并尝试在合盖连接外接显示器的场景下维持运行。
- 保存循环阈值、负载等级、GPU 开关和语言偏好。
- 持久化保存循环启动、阶段切换、完成、停止与故障记录。
- 支持简体中文与英文，并可检测 helper 版本更新。
- 启动时自动检查 GitHub Releases，可选择正式版、Beta 或 Alpha 更新通道，并可从“关于”页或应用菜单手动检查和下载新版本。

## 系统要求

- macOS 14.0 或更高版本，仅在macOS 26.6.1验证。
- Apple Silicon 或 Intel Mac（未验证）；充放电控制取决于机型是否提供兼容的 SMC 键。

## 构建

1. 使用 Xcode 打开 `BatteryForge.xcodeproj`。
2. 在项目签名设置中选择自己的 Development Team；如有需要，修改 App 与 helper 的 Bundle Identifier。
3. 选择 `BatteryForge` Scheme 和 `My Mac` 目标。
4. 构建并运行。

也可以进行不签名的命令行构建：

```sh
xcodebuild \
  -project BatteryForge.xcodeproj \
  -scheme BatteryForge \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  build
```

### 版本与 Build

发布版本只在准备发版时调整。帮助程序的发布版本由 Xcode 项目级 `BATTERYFORGE_HELPER_VERSION` 管理；macOS App 与帮助程序共用 `CURRENT_PROJECT_VERSION` 作为 Build 编号，同一版本下的修复递增 Build。例如 `0.0.5 (Build 2)` 与 `0.0.5 (Build 3)` 属于同一发布版本，安装检查会识别较新的 Build。CI 已通过 `CURRENT_PROJECT_VERSION="$GITHUB_RUN_NUMBER"` 注入构建编号，本地也可在 Xcode 或命令行覆盖。

帮助程序的 `--version` 输出发布版本，`--build` 输出 Build 编号；没有 Build 信息的旧安装会要求更新一次。后台服务通信需要有效的团队证书签名，上面的不签名构建仅用于编译验证和电池信息查看。

## 安全与隐私

BatteryForge 的监控和控制逻辑在本机运行。请勿在不了解 SMC 控制风险的情况下修改相关键值。温度过高、供电恢复失败或系统不支持时，应立即停止测试并确认电源状态。

## 许可证

本项目采用 [GNU General Public License v3.0](LICENSE) 发布。第三方组件仍遵循其各自许可证，详见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
