using System;
using System.Text;
using System.Runtime.InteropServices;
using System.Diagnostics;

public static class WebbyNative
{
    [DllImport("user32.dll")] public static extern bool DestroyIcon(IntPtr icon);
    private delegate bool EnumWindowsProc(IntPtr window, IntPtr parameter);
    [DllImport("user32.dll")] private static extern bool EnumWindows(EnumWindowsProc callback, IntPtr parameter);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] private static extern int GetWindowText(IntPtr window, StringBuilder text, int count);
    [DllImport("user32.dll")] private static extern bool IsWindowVisible(IntPtr window);
    [DllImport("user32.dll")] private static extern bool ShowWindow(IntPtr window, int command);
    [DllImport("user32.dll")] private static extern bool IsIconic(IntPtr window);
    [DllImport("user32.dll")] private static extern bool SetForegroundWindow(IntPtr window);
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr window, out uint pid);

    // Windows can refuse focus; return false so the caller can offer a new terminal.
    public static bool FocusOpenCode()
    {
        IntPtr match = IntPtr.Zero;
        EnumWindows((window, parameter) => {
            if (!IsWindowVisible(window)) return true;
            uint pid; GetWindowThreadProcessId(window, out pid);
            try {
                string process = Process.GetProcessById((int)pid).ProcessName.ToLowerInvariant();
                if (process != "windowsterminal" && process != "powershell" && process != "pwsh" &&
                    process != "cmd" && process != "opencode" && process != "conhost") return true;
            } catch (ArgumentException) { return true; }
            var title = new StringBuilder(512);
            GetWindowText(window, title, title.Capacity);
            string value = title.ToString();
            if (value.IndexOf("opencode", StringComparison.OrdinalIgnoreCase) >= 0 &&
                value.IndexOf("webby", StringComparison.OrdinalIgnoreCase) < 0) {
                match = window; return false;
            }
            return true;
        }, IntPtr.Zero);
        if (match == IntPtr.Zero) return false;
        if (IsIconic(match)) ShowWindow(match, 9);
        return SetForegroundWindow(match);
    }
}
