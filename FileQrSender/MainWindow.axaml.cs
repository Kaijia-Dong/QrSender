using Avalonia.Controls;
using Avalonia.Input;
using Avalonia.Interactivity;
using Avalonia.Media.Imaging;
using Avalonia.Platform.Storage;
using Avalonia.Threading;
using QRCoder;

namespace FileQrSender;

public partial class MainWindow : Window
{
    private readonly DispatcherTimer _timer = new();
    private TransmissionSession? _session;
    private int _timelineIndex;
    private bool _rendering;
    private bool _uiReady;

    public MainWindow()
    {
        InitializeComponent();
        _timer.Tick += async (_, _) => await NextFrameAsync();
        _uiReady = true;
        UpdateTimerInterval();
    }

    private async void ChooseFile_Click(object? sender, RoutedEventArgs e)
    {
        try
        {
            var files = await StorageProvider.OpenFilePickerAsync(new FilePickerOpenOptions
            {
                Title = "选择要通过二维码发送的文件",
                AllowMultiple = false
            });
            if (files.Count > 0 && files[0].TryGetLocalPath() is { } path) LoadFile(path);
        }
        catch (Exception exception) { ShowError("无法打开或读取所选文件", exception); }
    }

    private void Window_DragOver(object? sender, DragEventArgs e) => e.DragEffects = DragDropEffects.Copy;

    private void Window_Drop(object? sender, DragEventArgs e)
    {
        var file = e.Data.GetFiles()?.FirstOrDefault();
        try
        {
            if (file?.TryGetLocalPath() is { } path && File.Exists(path)) LoadFile(path);
        }
        catch (Exception exception) { ShowError("无法读取拖入的文件", exception); }
    }

    private void LoadFile(string path)
    {
        try
        {
            Stop();
            _session = new TransmissionSession(path, PayloadSize());
            FileNameText.Text = Path.GetFileName(path);
            FileInfoText.Text = $"{FormatSize(_session.FileLength)} · {_session.DataFrameCount:N0} 个数据帧 · SHA-256: {_session.FileHash[..16]}…";
            StatusText.Text = "已准备就绪。开始后请让手机持续扫描二维码。";
            FrameText.Text = "等待开始";
            StartButton.IsEnabled = true;
            Progress.Value = 0;
        }
        catch (Exception exception) { ShowError("无法准备该文件", exception); }
    }

    private async void StartButton_Click(object? sender, RoutedEventArgs e)
    {
        if (_session is null) return;
        _timelineIndex = 0;
        StartButton.IsEnabled = false;
        StopButton.IsEnabled = true;
        PayloadSizeCombo.IsEnabled = false;
        _timer.Start();
        await NextFrameAsync();
    }

    private void StopButton_Click(object? sender, RoutedEventArgs e) => Stop();

    private void Stop()
    {
        _timer.Stop();
        StartButton.IsEnabled = _session is not null;
        StopButton.IsEnabled = false;
        PayloadSizeCombo.IsEnabled = true;
    }

    private async Task NextFrameAsync()
    {
        if (_session is null || _rendering) return;
        _rendering = true;
        try
        {
            var frame = await Task.Run(() => _session.GetTimelineFrame(_timelineIndex++));
            var png = await Task.Run(() => CreateQrPng(frame.Encoded));
            using var stream = new MemoryStream(png);
            QrImage.Source = new Bitmap(stream);
            FrameText.Text = frame.Description;
            Progress.Value = (frame.DataIndex + 1d) / _session.DataFrameCount;
            StatusText.Text = $"正在发送，第 {frame.DataIndex + 1:N0} / {_session.DataFrameCount:N0} 个数据分片；可随时停止后重新开始。";
        }
        catch (Exception ex)
        {
            Stop();
            StatusText.Text = $"发送失败：{ex.Message}";
        }
        finally { _rendering = false; }
    }

    private void Setting_Changed(object? sender, SelectionChangedEventArgs e)
    {
        // XAML applies SelectedIndex while controls are being created; the other ComboBox may not exist yet.
        if (!_uiReady) return;
        UpdateTimerInterval();
        if (_session is not null) LoadFile(_session.FilePath);
    }

    private void UpdateTimerInterval() => _timer.Interval = TimeSpan.FromMilliseconds(1000d / Fps());
    private int PayloadSize() => PayloadSizeCombo.SelectedIndex switch { 0 => 300, 2 => 600, 3 => 900, 4 => 1200, _ => 450 };
    private int Fps() => FpsCombo.SelectedIndex switch { 0 => 5, 1 => 8, 2 => 10, 3 => 12, 4 => 15, 5 => 18, 7 => 24, 8 => 25, _ => 20 };
    private static byte[] CreateQrPng(string value) { using var generator = new QRCodeGenerator(); using var data = generator.CreateQrCode(value, QRCodeGenerator.ECCLevel.M); return new PngByteQRCode(data).GetGraphic(8); }
    private static string FormatSize(long size) => size < 1024 * 1024 ? $"{size / 1024d:F1} KB" : $"{size / 1024d / 1024d:F1} MB";
    private void Window_Closing(object? sender, WindowClosingEventArgs e) => _timer.Stop();
    private void ShowError(string message, Exception exception)
    {
        ErrorLog.Write(exception);
        StatusText.Text = $"{message}：{exception.Message}。详细日志已保存到“文稿/File QR Sender-error.log”。";
        Stop();
    }
}
