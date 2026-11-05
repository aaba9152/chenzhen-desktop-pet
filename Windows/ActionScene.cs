using System;
using System.Collections.Generic;
using System.Windows;
using System.Windows.Media;

namespace ChenzhenPet;

public sealed class ActionScene : FrameworkElement
{
    public Dictionary<string, ImageSource> Sprites { get; set; } = new();
    public SpritePose[] Poses { get; set; } = [];
    public Rect? Target { get; set; }
    public ActionScene() { IsHitTestVisible = false; }
    protected override void OnRender(DrawingContext dc)
    {
        if (Target is Rect target)
            dc.DrawRoundedRectangle(new SolidColorBrush(Color.FromArgb(30, 255, 150, 30)),
                new Pen(new SolidColorBrush(Color.FromArgb(180, 255, 150, 30)), 2), target, 12, 12);
        foreach (var p in Poses)
        {
            if (p.alpha <= .001 || p.width <= .01 || p.height <= .01) continue;
            dc.PushOpacity(p.alpha);
            dc.PushTransform(new TranslateTransform(p.center.x, p.center.y));
            dc.PushTransform(new RotateTransform(p.rotation));
            var rect = new Rect(-p.width/2, -p.height/2, p.width, p.height);
            if (p.sprite == "stream")
            {
                var geometry = new StreamGeometry();
                using (var path = geometry.Open())
                {
                    path.BeginFigure(new Point(-p.width*.15, -p.height/2), false, false);
                    path.BezierTo(new Point(p.width*.5, -p.height*.15), new Point(-p.width*.5, p.height*.15), new Point(p.width*.15, p.height/2), true, false);
                }
                dc.DrawGeometry(null, new Pen(new SolidColorBrush(Color.FromRgb(120, 56, 18)), p.width*.7) { StartLineCap = PenLineCap.Round, EndLineCap = PenLineCap.Round }, geometry);
            }
            else dc.DrawImage(Sprites[p.sprite], rect);
            dc.Pop(); dc.Pop(); dc.Pop();
        }
    }
}
