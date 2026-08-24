using Microsoft.Win32;

namespace PotatokenHub;

/// <summary>
/// Registers under the per-user Run key, the same mechanism the Startup folder
/// shortcut uses but without leaving a file behind to go stale.
/// </summary>
public static class LaunchAtLogin
{
    private const string KeyPath = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string ValueName = "potatoken hub";

    private static string ExecutablePath =>
        Environment.ProcessPath ?? System.Reflection.Assembly.GetEntryAssembly()!.Location;

    public static bool IsEnabled
    {
        get
        {
            try
            {
                using var key = Registry.CurrentUser.OpenSubKey(KeyPath);
                return key?.GetValue(ValueName) is not null;
            }
            catch (Exception e) when (e is System.Security.SecurityException or UnauthorizedAccessException)
            {
                return false;
            }
        }
    }

    public static void Toggle()
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(KeyPath, writable: true);
            if (key is null) return;

            if (IsEnabled) key.DeleteValue(ValueName, throwOnMissingValue: false);
            else key.SetValue(ValueName, $"\"{ExecutablePath}\"");
        }
        catch (Exception e) when (e is System.Security.SecurityException or UnauthorizedAccessException)
        {
        }
    }
}
