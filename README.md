# QrSender

通过二维码在 Windows 或 macOS 电脑与 iPhone 之间离线传输文件。

1. 在电脑上打开 File QR Sender，选择或拖入文件。发送端会循环显示二维码。
2. 在 iPhone 上打开 File QR Receiver，将相机对准电脑屏幕，直到接收完成。
3. 在 iPhone 上通过系统分享面板保存或分享收到的文件。

| 组件 | 平台 | 源码和说明 |
| --- | --- | --- |
| File QR Sender | Windows x64、macOS Apple Silicon | [发送端源码](FileQrSender/) · [构建与发布](#构建与发布) |
| File QR Receiver | iOS 17+ | [接收端源码与真机运行说明](FileQrReceiver/README.md) |

## 发送设置

发送参数提供 300/450/600/900/1200 bytes 每帧和 5–25 FPS；默认是 450 bytes、12 FPS。20 FPS 请配合 300 bytes 和近距离大屏；实际速度会因 Base64 编码、元数据、XOR 冗余与手机漏扫而降低；24/25 FPS 为实验模式。

发送端以“正序一轮、逆序一轮”交替播放。接收端按分片编号无序缓存，所以中间漏扫不会阻塞后续帧；尾部漏帧在下一轮逆序播放时会优先重现，显著缩短补齐等待。

## 构建与发布

开发机需安装 .NET 10 SDK。Windows 和 macOS 均发布为自包含应用，最终用户无需安装 .NET。

### Windows 10/11 x64

在 Windows PowerShell 执行：

```powershell
.\scripts\publish-windows.ps1
```

输出：`outputs\windows-x64\FileQrSender.exe`。支持 Windows 10 1607 及以上的官方支持版本和 Windows 11，要求 64 位系统。

### Mac Apple Silicon（M1/M2/M3/M4）

在 Apple Silicon Mac 的终端执行：

```bash
chmod +x scripts/publish-macos-arm64.sh
./scripts/publish-macos-arm64.sh
```

输出：`outputs/File QR Sender.app`，最低 macOS 11。该 `.app` 会包含 Avalonia 原生库与自包含 .NET 运行时；它不是“单一二进制”，这是 macOS 图形应用正确且可运行的打包形式。脚本默认生成**当前电脑可测试的临时签名版**；若应用之前被浏览器或 AirDrop 标记为隔离，可执行 `xattr -dr com.apple.quarantine "outputs/File QR Sender.app"` 后再打开。若要让其他用户在 Gatekeeper 下正常打开，应配置 `DEVELOPER_ID_APPLICATION` 后再运行脚本，并使用 Apple `notarytool` 完成公证、`stapler` 附加公证凭据。发行版可再压缩为 ZIP 或制作 DMG。

### 本地调试

```bash
dotnet restore FileQrSender/FileQrSender.csproj
dotnet run --project FileQrSender/FileQrSender.csproj
```

## FDQR v1 接收协议

二维码文字为 `FDQR1:` 加 Base64URL（无 `=` 填充）。解码后为小端序二进制包：

| 偏移 | 长度 | 字段 |
|---:|---:|---|
| 0 | 4 | ASCII `FDQR` |
| 4 | 1 | 版本：`1` |
| 5 | 1 | 类型：1=元数据、2=数据、3=XOR 冗余 |
| 6 | 2 | flags，当前为 0 |
| 8 | 8 | 会话 ID，UInt64 |
| 16 | 4 | 帧编号（数据编号；冗余帧为分组首编号） |
| 20 | 4 | 文件数据帧总数 |
| 24 | 2 | payload 长度，UInt16 |
| 26 | 4 | payload 的标准 CRC-32（IEEE） |
| 30 | N | payload |

元数据 payload 为 UTF-8 JSON，包括文件名、字节数、块大小、块数、每组冗余数和 SHA-256。数据 payload 为原始字节。每 8 个数据帧后插入一个等长（以零补齐）的 XOR 冗余帧；接收端可用它恢复该组内**恰好丢失 1 帧**的内容。每 20 个传输帧重复一次元数据帧。

接收端应按会话 ID 归类、先验证 CRC-32，收齐全部数据帧后按编号拼接、截断至元数据 `fileSize`，并验证最终 SHA-256。
