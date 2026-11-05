using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Media;

namespace ChenzhenPet;

public sealed partial class PetWindow
{
    private Window? clipPalette;
    private Button? paletteArrow;
    private void InitializeClipPalette(Grid root)
    {
        paletteArrow = new Button { Content = "◀", ToolTip = "展开或收起台词清单", Width = 30, Height = 30,
            HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Center,
            Margin = new Thickness(0, 0, 2, 0), Focusable = false };
        paletteArrow.Click += (_, _) => ToggleClipPalette();
        root.Children.Add(paletteArrow);
        LocationChanged += (_, _) => PositionClipPalette();
        SizeChanged += (_, _) => PositionClipPalette();
        Closed += (_, _) => { clipPalette?.Close(); clipPalette = null; };
    }
    private void ToggleClipPalette()
    {
        if (clipPalette?.IsVisible == true) { clipPalette.Hide(); PositionClipPalette(); return; }
        if (clipPalette == null)
        {
            var stack = new StackPanel { Background = new SolidColorBrush(Color.FromArgb(250,255,245,224)), Margin = new Thickness(4) };
            foreach (var clip in clips)
            {
                var button = new Button { Content = clip.label, Height = 30, Margin = new Thickness(2), Focusable = false };
                button.Click += (_, _) => { Play(clip); lastPortraitID = clip.id; };
                stack.Children.Add(button);
            }
            clipPalette = new Window { Width = 178, SizeToContent = SizeToContent.Height, WindowStyle = WindowStyle.None,
                ResizeMode = ResizeMode.NoResize, Topmost = true, ShowActivated = false, ShowInTaskbar = false,
                Focusable = false, Owner = this, Content = stack };
            clipPalette.SourceInitialized += (_, _) => {
                var h = new WindowInteropHelper(clipPalette).Handle;
                SetWindowLongPtr(h, -20, GetWindowLongPtr(h, -20) | 0x08000000 | 0x00000080);
            };
        }
        PositionClipPalette(); clipPalette.Show(); PositionClipPalette();
    }
    private void PositionClipPalette()
    {
        if (!double.IsFinite(Left) || !double.IsFinite(Top)) return;
        var area = CurrentScreen().WorkingArea; var dpi = VisualTreeHelper.GetDpi(this);
        double right = area.Right/dpi.DpiScaleX, left = area.Left/dpi.DpiScaleX;
        bool placeRight = Left + Width + 3 + (clipPalette?.Width ?? 178) <= right;
        if (clipPalette == null || !clipPalette.IsVisible) { if (paletteArrow != null) paletteArrow.Content = placeRight ? "▶" : "◀"; if (clipPalette == null) return; }
        clipPalette.Left = placeRight ? Left + Width + 3 : Math.Max(left, Left - clipPalette.Width - 3);
        double h = double.IsFinite(clipPalette.ActualHeight) && clipPalette.ActualHeight > 0 ? clipPalette.ActualHeight : clips.Length * 34 + 8;
        clipPalette.Top = Math.Clamp(Top + Height/2 - h/2, area.Top/dpi.DpiScaleY, Math.Max(area.Top/dpi.DpiScaleY, area.Bottom/dpi.DpiScaleY-h));
        if (paletteArrow != null && clipPalette.IsVisible) paletteArrow.Content = placeRight ? "◀" : "▶";
    }
}
