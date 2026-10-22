using System.Security.Principal;
using System.Text.Json;

namespace MacPet;

internal static class Program
{
    [STAThread]
    private static int Main(string[] args)
    {
        Application.SetUnhandledExceptionMode(UnhandledExceptionMode.ThrowException);
        Application.SetHighDpiMode(HighDpiMode.PerMonitorV2);
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        string? report = Value(args, "--report");
        if (args.Contains("--verify-release") || args.Contains("--smoke-test"))
        {
            try
            {
                if (args.Contains("--smoke-test")) Verification.Smoke(report!);
                else Verification.Run(report!);
                return 0;
            }
            catch (Exception error)
            {
                if (report != null) File.WriteAllText(report, JsonSerializer.Serialize(new { passed = false, error = error.ToString() }, Settings.Json));
                return 1;
            }
        }
        string sid = WindowsIdentity.GetCurrent().User?.Value ?? Environment.UserName;
        using var singleton = new Mutex(true, "Local\\MacPet.Instance." + sid, out bool first);
        using var restore = new EventWaitHandle(false, EventResetMode.AutoReset, "Local\\MacPet.Restore." + sid);
        if (!first) { restore.Set(); return 0; }
        try
        {
            var root = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "MacPet");
            using var pet = new PetWindow(root);
            var waiting = ThreadPool.RegisterWaitForSingleObject(restore, (_, _) =>
            {
                if (!pet.IsDisposed && pet.IsHandleCreated)
                    try { pet.BeginInvoke(pet.ShowPet); } catch (InvalidOperationException) { }
            }, null, Timeout.Infinite, false);
            try { Application.Run(pet); } finally { waiting.Unregister(null); }
        }
        catch (Exception error)
        {
            MessageBox.Show("MacPet 无法启动：\n" + error.Message, "MacPet", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
        finally { singleton.ReleaseMutex(); }
        return 0;
    }
    private static string? Value(string[] args, string name)
    {
        int index = Array.IndexOf(args, name);
        return index >= 0 && index + 1 < args.Length ? args[index + 1] : null;
    }
}
