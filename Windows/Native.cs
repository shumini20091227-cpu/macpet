using System.ComponentModel;
using System.Runtime.InteropServices;

namespace MacPet;

internal static class Native
{
    internal const int WmPowerBroadcast = 0x218, PowerSettingChange = 0x8013;
    internal const int WmMouseActivate = 0x21, MaNoActivate = 3;
    internal static readonly Guid DisplayState = new("6fe69556-704a-47a0-8f24-c28d936fda47");
    internal static readonly Guid EnergySaver = new("e00958c0-c213-4ace-ac77-fecced2eeea5");
    [StructLayout(LayoutKind.Sequential)] internal struct Point { public int X, Y; public Point(int x, int y) { X = x; Y = y; } }
    [StructLayout(LayoutKind.Sequential)] internal struct Size { public int Width, Height; public Size(int w, int h) { Width = w; Height = h; } }
    [StructLayout(LayoutKind.Sequential, Pack = 1)] internal struct Blend { public byte Op, Flags, Alpha, Format; }
    [StructLayout(LayoutKind.Sequential)] internal struct Rect { public int Left, Top, Right, Bottom; public Rectangle Bounds => Rectangle.FromLTRB(Left, Top, Right, Bottom); }
    [StructLayout(LayoutKind.Sequential)] private struct PowerStatus { public byte Ac, Flags, Life, Saver; public uint Remaining, Full; }
    internal delegate bool EnumWindowsProc(nint hwnd, nint parameter);
    internal delegate void WinEventProc(nint hook, uint eventId, nint hwnd, int objectId, int childId, uint threadId, uint time);

    [DllImport("user32.dll")] private static extern nint GetDC(nint hwnd);
    [DllImport("user32.dll")] private static extern int ReleaseDC(nint hwnd, nint dc);
    [DllImport("gdi32.dll")] private static extern nint CreateCompatibleDC(nint dc);
    [DllImport("gdi32.dll")] private static extern bool DeleteDC(nint dc);
    [DllImport("gdi32.dll")] private static extern nint SelectObject(nint dc, nint value);
    [DllImport("gdi32.dll")] private static extern bool DeleteObject(nint value);
    [DllImport("user32.dll", SetLastError = true)] private static extern bool UpdateLayeredWindow(nint hwnd, nint dstDc, ref Point dst, ref Size size, nint srcDc, ref Point src, uint key, ref Blend blend, uint flags);
    [DllImport("user32.dll")] internal static extern nint RegisterPowerSettingNotification(nint hwnd, ref Guid guid, uint flags);
    [DllImport("user32.dll")] internal static extern bool UnregisterPowerSettingNotification(nint handle);
    [DllImport("kernel32.dll")] private static extern bool GetSystemPowerStatus(out PowerStatus status);
    [DllImport("user32.dll")] internal static extern bool IsWindowVisible(nint hwnd);
    [DllImport("user32.dll")] private static extern bool IsIconic(nint hwnd);
    [DllImport("user32.dll")] private static extern bool GetWindowRect(nint hwnd, out Rect rect);
    [DllImport("user32.dll")] private static extern bool EnumWindows(EnumWindowsProc callback, nint parameter);
    [DllImport("user32.dll", EntryPoint = "GetWindowLongW")] private static extern int GetWindowLong(nint hwnd, int index);
    [DllImport("dwmapi.dll")] private static extern int DwmGetWindowAttribute(nint hwnd, int attribute, out uint value, int size);
    [DllImport("user32.dll")] internal static extern nint SetWinEventHook(uint min, uint max, nint module, WinEventProc callback, uint process, uint thread, uint flags);
    [DllImport("user32.dll")] internal static extern bool UnhookWinEvent(nint hook);

    internal static bool LowPower => GetSystemPowerStatus(out var status) && status.Saver == 1;

    internal static void Present(nint hwnd, Bitmap bitmap, System.Drawing.Point location)
    {
        var screen = GetDC(0);
        var memory = CreateCompatibleDC(screen);
        var handle = bitmap.GetHbitmap(Color.FromArgb(0));
        var previous = SelectObject(memory, handle);
        try
        {
            var size = new Size(bitmap.Width, bitmap.Height);
            var dst = new Point(location.X, location.Y);
            var src = new Point(0, 0);
            var blend = new Blend { Alpha = 255, Format = 1 };
            if (!UpdateLayeredWindow(hwnd, screen, ref dst, ref size, memory, ref src, 0, ref blend, 2))
                throw new Win32Exception(Marshal.GetLastWin32Error());
        }
        finally
        {
            SelectObject(memory, previous);
            DeleteObject(handle);
            DeleteDC(memory);
            ReleaseDC(0, screen);
        }
    }

    internal static bool IsFullyCovered(nint own, Rectangle bounds)
    {
        if (DwmGetWindowAttribute(own, 14, out var cloaked, sizeof(uint)) == 0 && cloaked != 0) return true;
        bool covered = false;
        EnumWindows((hwnd, _) =>
        {
            if (hwnd == own) return false;
            if (!IsWindowVisible(hwnd) || IsIconic(hwnd) || (GetWindowLong(hwnd, -20) & 0x80000) != 0) return true;
            if (DwmGetWindowAttribute(hwnd, 14, out var otherCloaked, sizeof(uint)) == 0 && otherCloaked != 0) return true;
            if (GetWindowRect(hwnd, out var rect) && rect.Bounds.Contains(bounds)) { covered = true; return false; }
            return true;
        }, 0);
        return covered;
    }
}
