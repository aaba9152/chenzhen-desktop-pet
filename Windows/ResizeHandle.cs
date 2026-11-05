using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;

namespace ChenzhenPet;

public sealed partial class PetWindow
{
    private void InitializeResizeHandle(Grid root)
    {
        var glyph = new TextBlock { Text = "◢", FontSize = 15, Foreground = new SolidColorBrush(Color.FromRgb(89,46,23)),
            HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
        var handle = new Border { Width = 20, Height = 20, Background = Brushes.Transparent, Child = glyph,
            HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Bottom,
            Cursor = Cursors.SizeNWSE, ToolTip = "拖动右下角调整大小" };
        bool dragging = false; NativePoint start = default; double width = 0;
        handle.PreviewMouseLeftButtonDown += (_, e) => {
            GetCursorPos(out start); width = Width; dragging = true; handle.CaptureMouse(); e.Handled = true;
        };
        handle.PreviewMouseMove += (_, e) => {
            if (!dragging || e.LeftButton != MouseButtonState.Pressed) return;
            GetCursorPos(out var now); var dpi = VisualTreeHelper.GetDpi(this);
            settings.Size = Placement.ResizeWidth(width, now.X-start.X, dpi.DpiScaleX);
            SizeTo(settings.Size); e.Handled = true;
        };
        handle.PreviewMouseLeftButtonUp += (_, e) => {
            if (!dragging) return; dragging = false; handle.ReleaseMouseCapture(); KeepVisible(); Save(); e.Handled = true;
        };
        handle.LostMouseCapture += (_, _) => { if (dragging) { dragging = false; KeepVisible(); Save(); } };
        root.Children.Add(handle);
    }
}
