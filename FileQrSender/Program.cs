using Avalonia;

namespace FileQrSender;

internal static class Program
{
    [STAThread]
    public static void Main(string[] args)
    {
        AppDomain.CurrentDomain.UnhandledException += (_, eventArgs) => ErrorLog.Write(eventArgs.ExceptionObject as Exception ?? new Exception(eventArgs.ExceptionObject?.ToString()));
        TaskScheduler.UnobservedTaskException += (_, eventArgs) => { ErrorLog.Write(eventArgs.Exception); eventArgs.SetObserved(); };
        try
        {
            BuildAvaloniaApp().StartWithClassicDesktopLifetime(args);
        }
        catch (Exception exception)
        {
            ErrorLog.Write(exception);
            throw;
        }
    }

    public static AppBuilder BuildAvaloniaApp() => AppBuilder.Configure<App>()
        .UsePlatformDetect()
        .WithInterFont()
        .LogToTrace();
}
