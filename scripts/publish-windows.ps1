$ErrorActionPreference = 'Stop'
$project = Join-Path $PSScriptRoot '..\FileQrSender\FileQrSender.csproj'
$output = Join-Path $PSScriptRoot '..\outputs\windows-x64'
dotnet publish $project -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:PublishTrimmed=false -o $output
Write-Host "Windows 发布完成：$output\FileQrSender.exe"
