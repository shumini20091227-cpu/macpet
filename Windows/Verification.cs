using System.Drawing.Imaging;
using System.Text.Json;
using Timer = System.Windows.Forms.Timer;

namespace MacPet;

internal static class Verification
{
    private static void Check(bool condition, string message) { if (!condition) throw new InvalidOperationException(message); }
    internal static void Run(string report)
    {
        string root = Path.Combine(Path.GetTempPath(), "MacPet-test-" + Guid.NewGuid());
        List<string> checks = [];
        try
        {
            var settings = Settings.Load(root);
            Check(settings.Speed == .5 && settings.EnergySaving && settings.PetSize == 220, "默认设置不一致");
            settings.X = 123; settings.Speed = .75; settings.Save(root);
            Check(Settings.Load(root).X == 123 && Settings.Load(root).Speed == .75, "设置保存失败"); checks.Add("settings persistence and defaults");
            var store = new ExpressionStore(root, settings, folder => Directory.Delete(folder, true)); store.Seed();
            var entries = store.Entries().Where(e => e.Id != ExpressionStore.Legacy).ToList();
            Check(entries.Count == 9, "应包含全部 9 个表情"); checks.Add("nine shared bundled expressions");
            foreach (var entry in entries)
            {
                using var animation = store.Load(entry);
                Check(animation.Frames.Count > 1 && animation.Duration > 0, "GIF 未解码为动画：" + entry.Name);
                Check(animation.Frames[0].GetPixel(0, 0).A == 0, "GIF 透明背景丢失");
                Check(animation.Index(animation.Duration + .001) == animation.Index(.001), "循环时间错误");
                Check(animation.NextDelay(0, 1, 6) >= 1.0 / 6, "省电帧上限错误");
            }
            checks.Add("all GIF frame counts, transparency, loop and low-power timing");
            using (var original = store.Load(store.Entries()[0])) Check(original.NextDelay(0, 1, 12) == null, "静态图片不应创建计时器");
            checks.Add("static-image timer disabled");
            var first = store.Import(entries[0].Path!); var second = store.Import(entries[0].Path!);
            Check(first.Id != second.Id && first.Name == second.Name, "同名表情不应覆盖");
            Check(store.Remove([first, second]).Count == 0, "批量删除失败");
            Check(File.Exists(entries[0].Path!), "删除导入副本不应删除来源");
            store.Remove([entries[0]]); store.Seed();
            Check(!store.Entries().Any(e => e.Id == entries[0].Id), "删除的内置表情重启后复活");
            Check(store.Entries().Any(e => e.Id == ExpressionStore.Legacy), "必须保留原版兜底"); checks.Add("import, same-name isolation, batch deletion, no resurrection, legacy fallback");
            settings.LeftGlint = new(.42f, .57f); settings.Save(root);
            Check(Math.Abs(Settings.Load(root).LeftGlint.X - .42f) < .001, "高光坐标未保留"); checks.Add("highlight settings persistence");
            using (var icon = Assets.Icon()) Check(icon.Width > 0, "图标缺失"); checks.Add("parrot application icon");
            File.WriteAllText(report, JsonSerializer.Serialize(new { passed = true, checks }, Settings.Json));
        }
        finally { if (Directory.Exists(root)) Directory.Delete(root, true); }
    }
    internal static void Smoke(string report)
    {
        string root = Path.Combine(Path.GetTempPath(), "MacPet-smoke-" + Guid.NewGuid());
        try
        {
            using var pet = new PetWindow(root);
            pet.Location = new(80, 80);
            Exception? failure = null;
            using var timer = new Timer { Interval = 2500 };
            timer.Tick += (_, _) =>
            {
                timer.Stop();
                try
                {
                    Check(pet.RenderCount > 1, "窗口没有实际换帧");
                    pet.SavePreview(Path.Combine(Path.GetDirectoryName(report)!, "windows-preview.png"));
                    using var menu = pet.BuildMenu();
                    string text = string.Join("|", menu.Items.Cast<ToolStripItem>().Select(i => i.Text));
                    Check(text.Contains("切换表情") && text.Contains("动画速度") && text.Contains("省电模式"), "菜单功能不完整");
                    Check(!text.Contains("专注") && !text.Contains("番茄"), "旧功能不应恢复");
                    pet.HidePet(); Check(!pet.FrameTimerRunning, "隐藏后计时器未停止");
                    pet.ShowPet(); Check(pet.FrameTimerRunning, "恢复显示后动画未继续");
                    File.WriteAllText(report, JsonSerializer.Serialize(new { passed = true, renderedFrames = pet.RenderCount, menu = text, transparentLayeredWindow = true }, Settings.Json));
                }
                catch (Exception error) { failure = error; }
                finally { pet.Close(); }
            };
            pet.Shown += (_, _) => timer.Start();
            Application.Run(pet);
            if (failure != null) throw failure;
        }
        finally { if (Directory.Exists(root)) Directory.Delete(root, true); }
    }
}
