# QrSender

用电脑屏幕和 iPhone 相机离线传文件。电脑把文件拆成一系列二维码，iPhone 连续扫码并还原文件。传输过程无需联网或连接数据线。

| 应用 | 平台 | 目录 |
| --- | --- | --- |
| File QR Sender | Windows 10/11 x64、macOS 11+（Apple Silicon） | [桌面端源码](FileQrSender/) |
| File QR Receiver | iOS 17+ | [iOS 真机安装说明](FileQrReceiver/README.md) |

## 使用方法

1. 在电脑上打开 File QR Sender，选择或拖入一个文件，让二维码持续播放。
2. 在 iPhone 上打开 File QR Receiver，允许相机访问，将镜头对准电脑屏幕。
3. 等待接收完成，通过系统分享面板保存到「文件」或发送给其他应用。

第一次传输可使用默认设置，每帧 450 字节、每秒 12 帧。如果频繁漏扫，可以降低播放帧率，或把每帧数据量调到 300 字节。发送端交替正序和逆序播放，方便接收端在下一轮补齐遗漏的分片。

## 从源码构建

### 桌面发送端

安装 .NET 10 SDK，从仓库根目录执行对应平台的打包脚本。打包后的应用自带运行时。

**Windows x64（PowerShell）**

```powershell
.\scripts\publish-windows.ps1
```

生成 `outputs/windows-x64/FileQrSender.exe`。

**macOS Apple Silicon**

```bash
./scripts/publish-macos-arm64.sh
```

生成 `outputs/File QR Sender.app`。脚本默认生成供本机测试的临时签名版本。对外分发时，可通过 `DEVELOPER_ID_APPLICATION` 指定签名身份，再完成 Apple 公证。

本地调试可运行 `dotnet run --project FileQrSender/FileQrSender.csproj`。

### iOS 接收端

在 Xcode 中打开 `FileQrReceiver/FileQrReceiver.xcodeproj`，配置自己的签名团队与 Bundle Identifier，再选择 iPhone 真机运行。相机扫码流程需要在真机上验证。完整步骤见 [iOS 接收端说明](FileQrReceiver/README.md)。

## 传输协议

两端使用 FDQR v1。接收端使用 CRC-32 校验每帧，利用 XOR 冗余恢复每组中漏扫的一帧，并在文件拼接完成后校验 SHA-256。帧格式和元数据见 [FDQR v1 协议](docs/FDQR-v1.md)。
