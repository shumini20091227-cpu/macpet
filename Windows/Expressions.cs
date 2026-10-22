using System.Drawing.Imaging;
using System.Drawing.Drawing2D;
using System.Reflection;
using System.Text.Json;
using Microsoft.VisualBasic.FileIO;

namespace MacPet;

internal static class Assets
{
    internal static Stream Open(string name) => Assembly.GetExecutingAssembly().GetManifestResourceStream("MacPet.Assets." + name)
        ?? throw new FileNotFoundException("缺少内置资源：" + name);
    internal static byte[] Bytes(string name) { using var source = Open(name); using var output = new MemoryStream(); source.CopyTo(output); return output.ToArray(); }
    internal static Icon Icon() { using var stream = Open("MacPet.ico"); using var icon = new Icon(stream); return (Icon)icon.Clone(); }
}

internal sealed class Animation : IDisposable
{
    internal readonly List<Bitmap> Frames = [];
    internal readonly List<double> Ends = [];
    internal double Duration => Ends[^1];
    internal Animation(Stream stream)
    {
        try
        {
            using var image = Image.FromStream(stream, true, true);
            if (image.Width < 1 || image.Height < 1 || image.Width > 4096 || image.Height > 4096) throw new InvalidDataException("单帧最大 4096×4096。");
            bool timed = image.FrameDimensionsList.Contains(FrameDimension.Time.Guid);
            int count = timed ? image.GetFrameCount(FrameDimension.Time) : 1;
            if (count < 1 || count > 1000 || (long)image.Width * image.Height * 4 * count > 256L * 1024 * 1024)
                throw new InvalidDataException("最多 1000 帧，解码后总大小不超过 256 MB。");
            byte[] delays = [];
            if (timed && image.PropertyIdList.Contains(0x5100)) delays = image.GetPropertyItem(0x5100)?.Value ?? [];
            double elapsed = 0;
            for (int i = 0; i < count; i++)
            {
                if (timed) image.SelectActiveFrame(FrameDimension.Time, i);
                var frame = new Bitmap(image.Width, image.Height, PixelFormat.Format32bppPArgb);
                try
                {
                    using var graphics = Graphics.FromImage(frame);
                    graphics.CompositingMode = CompositingMode.SourceCopy;
                    graphics.Clear(Color.Transparent);
                    graphics.DrawImage(image, new Rectangle(0, 0, frame.Width, frame.Height));
                    Frames.Add(frame);
                }
                catch { frame.Dispose(); throw; }
                double delay = delays.Length >= (i + 1) * 4 ? BitConverter.ToUInt32(delays, i * 4) / 100.0 : 0.1;
                elapsed += delay >= 0.02 ? delay : 0.1;
                Ends.Add(elapsed);
            }
        }
        catch { Dispose(); throw; }
    }
    internal static Animation FromFile(string path) { using var stream = File.OpenRead(path); return new(stream); }
    internal int Index(double elapsed)
    {
        var position = double.IsFinite(elapsed) ? Math.Max(0, elapsed) % Duration : 0;
        int index = Ends.FindIndex(end => position < end);
        return index >= 0 ? index : 0;
    }
    internal double? NextDelay(double elapsed, double speed, double fps)
    {
        if (Frames.Count <= 1) return null;
        var position = Math.Max(0, elapsed) % Duration;
        return Math.Max(1 / fps, (Ends[Index(elapsed)] - position) / speed + .001);
    }
    public void Dispose() { foreach (var frame in Frames) frame.Dispose(); Frames.Clear(); }
}

internal sealed record Expression(string Id, string Name, string? Path)
{
    public override string ToString() => Name;
}
internal sealed record Pack(string DefaultExpressionID, List<PackExpression> Expressions);
internal sealed record PackExpression(string Id, string Name, string File);

internal sealed class ExpressionStore
{
    internal const string Legacy = "legacy";
    internal readonly string Root;
    internal readonly Settings Settings;
    internal readonly Pack Pack;
    private readonly Action<string> recycle;
    internal string DirectoryPath => Path.Combine(Root, "Expressions");
    internal string CustomPath => Path.Combine(Root, "custom_character.png");
    internal ExpressionStore(string root, Settings settings, Action<string>? recycle = null)
    {
        Root = root; Settings = settings;
        this.recycle = recycle ?? (path => FileSystem.DeleteDirectory(path, UIOption.OnlyErrorDialogs, RecycleOption.SendToRecycleBin, UICancelOption.ThrowException));
        using var stream = Assets.Open("expression-pack.json");
        Pack = JsonSerializer.Deserialize<Pack>(stream, MacPet.Settings.Json) ?? throw new InvalidDataException("内置表情清单无效。");
    }
    internal void Seed()
    {
        foreach (var entry in Pack.Expressions.Where(e => !Settings.InstalledPackIds.Contains(e.Id)))
        {
            if (!Guid.TryParse(entry.Id, out _) || System.IO.Path.GetFileName(entry.File) != entry.File) throw new InvalidDataException("内置表情路径无效。");
            string folder = System.IO.Path.Combine(DirectoryPath, entry.Id);
            if (!Directory.Exists(folder))
            {
                Directory.CreateDirectory(folder);
                try { File.WriteAllBytes(System.IO.Path.Combine(folder, SafeName(entry.Name) + System.IO.Path.GetExtension(entry.File)), Assets.Bytes(entry.File)); }
                catch { Directory.Delete(folder, true); throw; }
            }
            Settings.InstalledPackIds.Add(entry.Id);
            Settings.Save(Root);
        }
    }
    private static string SafeName(string name) => string.Concat(name.Select(c => System.IO.Path.GetInvalidFileNameChars().Contains(c) ? '_' : c));
    internal List<Expression> Entries()
    {
        List<Expression> entries = [new(Legacy, "原版形象", null)];
        if (Directory.Exists(DirectoryPath))
        {
            var imported = Directory.EnumerateDirectories(DirectoryPath).Where(p => Guid.TryParse(System.IO.Path.GetFileName(p), out _))
                .SelectMany(folder => Directory.EnumerateFiles(folder).Where(Supported)
                    .Select(path => new Expression(System.IO.Path.GetFileName(folder), System.IO.Path.GetFileNameWithoutExtension(path), path)))
                .OrderBy(e => e.Name, StringComparer.CurrentCultureIgnoreCase);
            entries.AddRange(imported);
        }
        return entries;
    }
    internal static bool Supported(string path) => new[] { ".gif", ".png" }.Contains(System.IO.Path.GetExtension(path).ToLowerInvariant());
    internal Expression Initial() => Entries().FirstOrDefault(e => e.Id == Settings.SelectedExpression)
        ?? Entries().FirstOrDefault(e => e.Id == Pack.DefaultExpressionID) ?? Entries()[0];
    internal Animation Load(Expression entry)
    {
        if (entry.Path != null) return Animation.FromFile(entry.Path);
        if (File.Exists(CustomPath)) return Animation.FromFile(CustomPath);
        using var stream = Assets.Open("pet_character.png"); return new(stream);
    }
    internal Expression Import(string source)
    {
        if (!Supported(source)) throw new InvalidDataException("请选择 GIF 或 PNG。");
        using (Animation.FromFile(source)) { }
        string id = Guid.NewGuid().ToString(), folder = System.IO.Path.Combine(DirectoryPath, id);
        Directory.CreateDirectory(folder);
        var destination = System.IO.Path.Combine(folder, System.IO.Path.GetFileName(source));
        try { File.Copy(source, destination); }
        catch { Directory.Delete(folder, true); throw; }
        return new(id, System.IO.Path.GetFileNameWithoutExtension(source), destination);
    }
    internal List<string> Remove(IEnumerable<Expression> selected)
    {
        List<string> failures = [];
        foreach (var entry in selected.DistinctBy(e => e.Id).Where(e => e.Id != Legacy))
        {
            try
            {
                if (!Guid.TryParse(entry.Id, out _)) throw new InvalidDataException("表情 ID 无效。");
                recycle(System.IO.Path.Combine(DirectoryPath, entry.Id));
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or OperationCanceledException or InvalidDataException)
            { failures.Add(entry.Name); }
        }
        return failures;
    }
}
