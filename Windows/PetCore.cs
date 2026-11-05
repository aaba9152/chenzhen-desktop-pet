using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;

namespace ChenzhenPet;

public record Clip(int id, string label, string file, double duration);
public record Portrait(string id, string name, string file, double[] mouth, double[] head);

// Plays clip IDs in the shared manifest order.
public sealed class ClipSequence
{
    private readonly List<int> remaining = new();
    public ClipSequence(int? seed = null) { }
    public int Next(int[] ids)
    {
        if (ids.Length == 0 || ids.Distinct().Count() != ids.Length) throw new ArgumentException("Invalid clip IDs");
        remaining.RemoveAll(x => !ids.Contains(x));
        if (remaining.Count == 0) remaining.AddRange(ids);
        int value = remaining[0]; remaining.RemoveAt(0); return value;
    }

}

public static class FeedingReply
{
    public static int Select(string action, int? lastPortraitID, int fallback) =>
        action == "pour" ? 3 : lastPortraitID == 6 ? (action == "soda" ? 2 : 4) : action == "noodles" ? 1 : fallback;
}

public sealed class Preferences
{
    public double Volume { get; set; } = .5;
    public double Size { get; set; } = 260;
    public string PortraitID { get; set; } = "original";
    public double? X { get; set; }
    public double? Y { get; set; }
    public void Sanitize()
    {
        Volume = double.IsFinite(Volume) ? Math.Clamp(Volume, 0, 1) : .5;
        if (string.IsNullOrEmpty(PortraitID)) PortraitID = "original";
        Size = double.IsFinite(Size) ? Math.Clamp(Size, 190, 340) : 260;
        if (X is double x && !double.IsFinite(x)) X = null;
        if (Y is double y && !double.IsFinite(y)) Y = null;
    }
    public static Preferences Read(string path)
    {
        try { var value = JsonSerializer.Deserialize<Preferences>(File.ReadAllText(path)) ?? new(); value.Sanitize(); return value; }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or JsonException) { return new(); }
    }
    public void Save(string path)
    {
        Sanitize(); Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        string temp = path + ".tmp";
        File.WriteAllText(temp, JsonSerializer.Serialize(this, new JsonSerializerOptions { WriteIndented = true }));
        File.Move(temp, path, true);
    }
}

public static class Placement
{
    public static (double x, double y) Clamp(double x, double y, double width, double height,
        double left, double top, double areaWidth, double areaHeight) =>
        (Math.Clamp(x, left, Math.Max(left, left + areaWidth - width)),
         Math.Clamp(y, top, Math.Max(top, top + areaHeight - height)));
    public static SceneRect AvatarRect(double width, double height, double ratio)
    {
        double unit = width / 260, slotWidth = width - 16, slotHeight = height - 52 - 114 * unit;
        double fittedWidth = Math.Min(slotWidth, slotHeight / ratio), fittedHeight = fittedWidth * ratio;
        return new SceneRect(8 + (slotWidth - fittedWidth) / 2, 44 + 70 * unit + slotHeight - fittedHeight, fittedWidth, fittedHeight);
    }
    public static double ResizeWidth(double initialWidth, double physicalDX, double dpiScale) => Math.Clamp(initialWidth + physicalDX / dpiScale, 190, 340);
    public static bool IsDrag(double dx, double dy, double dpiScale) => Math.Sqrt(dx * dx + dy * dy) > 4 * dpiScale;
}
