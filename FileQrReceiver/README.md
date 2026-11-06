# File QR Receiver（iOS）

原生 iOS 17+ 接收端，兼容同仓库 Windows/macOS 发送端的 FDQR v1 协议。

## 功能

- AVFoundation 连续扫码；识别 `FDQR1:` 二维码帧。
- CRC-32 校验、按会话聚合与重复帧去重。
- 每组 8 帧的 XOR 冗余补偿：每组恰好漏扫 1 个数据帧时自动恢复。
- 按编号无序缓存后续分片；发送端交替正序/逆序播放，尾部漏帧在下一轮会优先补发。
- 收齐后拼接文件、SHA-256 完整性校验并保存到 App 的 Documents/Received。
- 使用 iOS 系统分享面板，因此若设备安装微信，完成后可从分享面板选择微信；也支持“存储到文件”、AirDrop 和其他支持该文件类型的 App。

## 打开项目

安装 Xcode 后，在此目录打开仓库自带的工程：

```bash
open FileQrReceiver.xcodeproj
```

如果修改了 `project.yml`，可以用 XcodeGen 重新生成工程：

```bash
brew install xcodegen
xcodegen generate
```

在 Xcode 中选择真机、设置你自己的 Signing Team 和 Bundle Identifier 后运行。相机扫码必须使用真机，模拟器不能验证相机流程。
