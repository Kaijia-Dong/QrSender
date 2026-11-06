namespace FileQrSender;

internal static class ErrorLog
{
    private static readonly string LogPath = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments),
        "File QR Sender-error.log");

    public static void Write(Exception exception)
    {
        try
        {
            File.AppendAllText(LogPath, $"[{DateTimeOffset.Now:O}]{Environment.NewLine}{exception}{Environment.NewLine}{Environment.NewLine}");
        }
        catch { /* Never replace the original failure with a logging failure. */ }
    }
}
