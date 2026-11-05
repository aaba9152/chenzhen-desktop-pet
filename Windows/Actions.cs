using System;
using System.Collections.Generic;
using System.Linq;

namespace ChenzhenPet;

public record ActionFrame(double t, string anchor, double x, double y, double sx, double sy, double rotation, double alpha);
public record ActionLayer(string sprite, double width, double height, ActionFrame[] frames);
public record FeedingAction(string id, string title, string icon, double iconRotation, double duration, ActionLayer[] layers);
public record ActionLibrary(int version, int fps, int[] responses, Dictionary<string, double[]> anchors, FeedingAction[] actions)
{
    public void Validate()
    {
        if (version != 1 || fps != 30 || !responses.SequenceEqual(new[] { 2, 3 }) || actions.Length != 4 || actions.Select(a => a.id).Distinct().Count() != 4 || !anchors.ContainsKey("mouth") || !anchors.ContainsKey("head")) throw new ArgumentException("Invalid action manifest");
        foreach (var a in actions)
        {
            if (a.duration <= 0 || a.layers.Length == 0) throw new ArgumentException("Invalid action");
            foreach (var layer in a.layers)
            {
                if (layer.width <= 0 || layer.height <= 0 || layer.frames.Length < 2 || layer.frames[0].t != 0 || layer.frames[^1].t != a.duration) throw new ArgumentException("Invalid layer");
                for (int i = 1; i < layer.frames.Length; i++) if (layer.frames[i-1].t >= layer.frames[i].t) throw new ArgumentException("Unsorted keyframes");
                foreach (var f in layer.frames)
                    if ((f.anchor != "start" && (!anchors.TryGetValue(f.anchor, out var point) || point.Length != 2)) || !new[] { f.t, f.x, f.y, f.sx, f.sy, f.rotation, f.alpha }.All(double.IsFinite)) throw new ArgumentException("Invalid keyframe");
            }
        }
    }
}
public record struct ScenePoint(double x, double y);
public record struct SceneRect(double x, double y, double width, double height)
{
    public bool Contains(ScenePoint p) => p.x >= x && p.y >= y && p.x < x + width && p.y < y + height;
}
public record SpritePose(string sprite, ScenePoint center, double width, double height, double rotation, double alpha);
public static class ActionSampler
{
    public static double Squash(double t, double duration = double.PositiveInfinity) => 1 - .06 * (1 - Math.Cos(t * 2 * Math.PI / .35)) * Math.Min(1,Math.Max(0,(duration-t)/.22));
    public static SpritePose[] Sample(FeedingAction action, double time, ActionLibrary library, SceneRect avatar, ScenePoint start, double unit, double squash)
    {
        ScenePoint Location(ActionFrame f)
        {
            var p = f.anchor == "start" ? start : new ScenePoint(avatar.x + library.anchors[f.anchor][0] * avatar.width,
                avatar.y + avatar.height - (1-library.anchors[f.anchor][1]) * avatar.height * squash);
            return new(p.x + f.x * unit, p.y + f.y * unit);
        }
        return action.layers.Select(layer =>
        {
            double t = Math.Clamp(time, 0, action.duration);
            int i = Math.Clamp(Array.FindLastIndex(layer.frames, f => f.t <= t), 0, layer.frames.Length - 2);
            var a = layer.frames[i]; var b = layer.frames[i+1];
            double raw = Math.Clamp((t-a.t)/(b.t-a.t), 0, 1), u = raw * raw * (3 - 2*raw);
            double Lerp(double x, double y) => x + (y-x)*u;
            var p = Location(a); var q = Location(b);
            return new SpritePose(layer.sprite, new(Lerp(p.x,q.x), Lerp(p.y,q.y)), layer.width*unit*Lerp(a.sx,b.sx),
                layer.height*unit*Lerp(a.sy,b.sy), Lerp(a.rotation,b.rotation), Lerp(a.alpha,b.alpha));
        }).ToArray();
    }
}

// One generation owns audio, captions and scene; late callbacks may not affect a new interaction.
public sealed class InteractionGeneration
{
    public long Value { get; private set; }
    public long Next() => ++Value;
    public bool IsCurrent(long token) => token == Value;
}
