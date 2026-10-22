using System.Text.Json;

namespace MacPet;

internal sealed class Settings
{
    public string SelectedExpression { get; set; } = "";
    public double Speed { get; set; } = 0.5;
    public bool EnergySaving { get; set; } = true;
    public double PetSize { get; set; } = 220;
    public int? X { get; set; }
    public int? Y { get; set; }
    public bool Hidden { get; set; }
    public PointF LeftGlint { get; set; } = new(0.372f, 0.542f);
    public PointF RightGlint { get; set; } = new(0.615f, 0.536f);
    public HashSet<string> InstalledPackIds { get; set; } = [];
    internal static readonly JsonSerializerOptions Json = new() { WriteIndented = true, IncludeFields = true, PropertyNameCaseInsensitive = true };
    internal static Settings Load(string root)
    {
        try
        {
            var path = Path.Combine(root, "settings.json");
            if (!File.Exists(path)) return new();
            var value = JsonSerializer.Deserialize<Settings>(File.ReadAllText(path), Json) ?? new();
            value.PetSize = double.IsFinite(value.PetSize) ? Math.Clamp(value.PetSize, 100, 560) : 220;
            if (!new[] { 0.25, 0.5, 0.75, 1.0 }.Contains(value.Speed)) value.Speed = 0.5;
            value.InstalledPackIds ??= [];
            value.LeftGlint = ClampGlint(value.LeftGlint, new(0.372f, 0.542f));
            value.RightGlint = ClampGlint(value.RightGlint, new(0.615f, 0.536f));
            return value;
        }
        catch (JsonException) { return new(); }
        catch (IOException) { return new(); }
    }
    internal static PointF ClampGlint(PointF point, PointF fallback)
        => float.IsFinite(point.X) && float.IsFinite(point.Y)
            ? new(Math.Clamp(point.X, .18f, .82f), Math.Clamp(point.Y, .32f, .72f)) : fallback;
    internal void Save(string root)
    {
        Directory.CreateDirectory(root);
        var temporary = Path.Combine(root, "settings.json.tmp");
        File.WriteAllText(temporary, JsonSerializer.Serialize(this, Json));
        File.Move(temporary, Path.Combine(root, "settings.json"), true);
    }
}
