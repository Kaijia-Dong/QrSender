#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
project="$root/FileQrSender/FileQrSender.csproj"
publish_dir="$root/work/publish/osx-arm64"
bundle="$root/outputs/File QR Sender.app"
dotnet_cmd="${DOTNET_CMD:-dotnet}"
if ! command -v "$dotnet_cmd" >/dev/null 2>&1; then
  if [[ -x /usr/local/share/dotnet/dotnet ]]; then dotnet_cmd=/usr/local/share/dotnet/dotnet
  elif [[ -x /usr/local/bin/dotnet ]]; then dotnet_cmd=/usr/local/bin/dotnet
  else echo "未找到 .NET 10 SDK；请安装后重试。" >&2; exit 1
  fi
fi

# Avalonia requires its native macOS libraries at application startup. Do not use .NET single-file
# publishing here: publish a self-contained directory and turn that directory into a standard .app bundle.
"$dotnet_cmd" publish "$project" -c Release -r osx-arm64 --self-contained true -p:PublishSingleFile=false -p:PublishTrimmed=false -o "$publish_dir"
rm -rf "$bundle"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
cp "$root/macos/Info.plist" "$bundle/Contents/Info.plist"
cp "$root/macos/AppIcon.icns" "$bundle/Contents/Resources/AppIcon.icns"
# Preserve every managed/native runtime dependency and any symbolic links. The executable remains
# exactly where macOS requires it: Contents/MacOS/FileQrSender.
ditto "$publish_dir" "$bundle/Contents/MacOS"
chmod +x "$bundle/Contents/MacOS/FileQrSender"

if [[ -n "${DEVELOPER_ID_APPLICATION:-}" ]]; then
  signing_identity="$DEVELOPER_ID_APPLICATION"
  signing_flags=(--force --options runtime --timestamp --sign "$signing_identity")
  # A self-contained .NET publish includes managed assemblies and JSON manifests in MacOS;
  # sign the complete runtime closure, then the application bundle.
  codesign --force --deep --options runtime --timestamp --sign "$signing_identity" "$bundle"
  codesign --verify --deep --strict --verbose=2 "$bundle"
  echo "已使用 Developer ID 签名。请随后用 notarytool 公证并 stapler 附加凭据。"
else
  # Makes a locally built app executable by the current Mac without an Apple Developer certificate.
  # It is intentionally not suitable for sharing with other users.
  codesign --force --deep --sign - "$bundle"
  codesign --verify --deep --strict --verbose=2 "$bundle"
  xattr -dr com.apple.quarantine "$bundle" 2>/dev/null || true
  echo "本机测试版已生成并使用临时签名：$bundle"
  echo "它只适合当前电脑测试；对外发布仍须设置 DEVELOPER_ID_APPLICATION、签名并公证。"
fi
