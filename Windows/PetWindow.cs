using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using Forms = System.Windows.Forms;

namespace ChenzhenPet;

public sealed partial class PetWindow : Window
{
    private readonly Clip[] clips;
    private readonly Portrait[] portraits;
    private readonly Dictionary<string, BitmapImage> portraitImages = new();
    private readonly Dictionary<int, byte[]> audioBytes = new();
    private readonly ClipSequence bag = new();
    private readonly Preferences settings;
    private readonly string settingsPath = Path.Combine(Program.DataDirectory, "settings.json");
    private readonly Image face;
    private readonly Border bubble;
    private readonly TextBlock caption;
    private readonly ScaleTransform squash = new(1, 1);
    private readonly Forms.NotifyIcon tray;
    private long? current;
    private int? lastPortraitID;
    private FastAudio? audio;
    private DispatcherTimer? audioTimer;
    private readonly InteractionGeneration interaction = new();
    private long generation => interaction.Value;
    private bool pointerDown, dragged;
    private NativePoint initialMouse;
    private double initialLeft, initialTop;
    private double ratio;
    private bool shuttingDown;

    private static Stream Resource(string name) => Assembly.GetExecutingAssembly().GetManifestResourceStream("Pet." + name)
        ?? throw new InvalidDataException("Missing embedded resource: " + name);

    public PetWindow()
    {
        using (var stream = Resource("clips.json")) clips = JsonSerializer.Deserialize<Clip[]>(stream) ?? throw new InvalidDataException("台词列表为空");
        if (clips.Length != 6 || clips.Select(c => c.id).Distinct().Count() != clips.Length) throw new InvalidDataException("台词列表无效");
        settings = Preferences.Read(settingsPath);
        Directory.CreateDirectory(Program.DataDirectory);
        // Decode the six embedded WAVs once; playback never waits for per-click disk IO.
        foreach (var clip in clips)
        {
            if (Path.GetFileName(clip.file) != clip.file || clip.duration <= 0 || !double.IsFinite(clip.duration)) throw new InvalidDataException("台词配置无效");
            using var stream = Resource(clip.file); using var bytes = new MemoryStream(); stream.CopyTo(bytes);
            audioBytes[clip.id] = bytes.ToArray();
        }
        try { audio = new FastAudio(audioBytes); } catch (Exception e) { Program.Log(e); }
        using (var stream = Resource("portraits.json")) portraits = JsonSerializer.Deserialize<Portrait[]>(stream) ?? throw new InvalidDataException("头像配置为空");
        if (portraits.Length == 0 || portraits.Select(p => p.id).Distinct().Count() != portraits.Length) throw new InvalidDataException("头像配置无效");
        foreach (var portrait in portraits)
        {
            if (portrait.file.Contains("..") || portrait.mouth.Length != 2 || portrait.head.Length != 2) throw new InvalidDataException("头像配置无效");
            var image = new BitmapImage(); using var stream = Resource(portrait.file.Replace('/', '.'));
            image.BeginInit(); image.CacheOption = BitmapCacheOption.OnLoad; image.StreamSource = stream; image.EndInit(); image.Freeze();
            portraitImages[portrait.id] = image;
        }
        if (!portraitImages.ContainsKey(settings.PortraitID)) settings.PortraitID = "original";
        var bitmap = portraitImages[settings.PortraitID];
        ratio = (double)bitmap.PixelHeight / bitmap.PixelWidth;
        Title = "陈震桌宠"; WindowStyle = WindowStyle.None; ResizeMode = ResizeMode.NoResize;
        AllowsTransparency = true; Background = Brushes.Transparent; Topmost = true;
        ShowActivated = false; ShowInTaskbar = false; Focusable = false;
        WindowStartupLocation = WindowStartupLocation.Manual;
        var root = new Grid { Background = Brushes.Transparent, ToolTip = "点击按顺序说一句 · 拖动移动 · 右键设置" };
        face = new Image { Source = bitmap, Stretch = Stretch.Uniform, Margin = new Thickness(8, 44, 8, 8),
            RenderTransformOrigin = new Point(.5, 1), RenderTransform = squash, IsHitTestVisible = false };
        caption = new TextBlock { Foreground = new SolidColorBrush(Color.FromRgb(71,33,13)), FontSize = 15, FontWeight = FontWeights.Heavy,
            TextAlignment = TextAlignment.Center, TextWrapping = TextWrapping.Wrap, VerticalAlignment = VerticalAlignment.Center,
            Effect = new System.Windows.Media.Effects.DropShadowEffect { Color = Color.FromRgb(255,201,122), BlurRadius = 0, ShadowDepth = 1, Opacity = 1 } };
        var bubbleBitmap = new BitmapImage();
        using (var stream = Resource("caption-bubble.png"))
        { bubbleBitmap.BeginInit(); bubbleBitmap.CacheOption = BitmapCacheOption.OnLoad; bubbleBitmap.StreamSource = stream; bubbleBitmap.EndInit(); bubbleBitmap.Freeze(); }
        caption.HorizontalAlignment = HorizontalAlignment.Center;
        bubble = new Border { Background = new ImageBrush(bubbleBitmap) { Stretch = Stretch.Fill },
            Padding = new Thickness(20, 4, 20, 10), HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Top,
            Height = 56, Visibility = Visibility.Hidden, Child = caption, IsHitTestVisible = false };
        root.Children.Add(face); root.Children.Add(bubble); Content = root;
        SizeTo(settings.Size);
        InitializeFeeding(root);
        SetPortraitAnchors(portraits.First(p => p.id == settings.PortraitID));
        InitializeClipPalette(root);
        InitializeResizeHandle(root);
        root.MouseLeftButtonDown += PointerDown;
        root.MouseMove += PointerMove;
        root.MouseLeftButtonUp += PointerUp;
        root.LostMouseCapture += (_, _) => pointerDown = false;
        root.MouseRightButtonUp += (_, e) => { ShowMenu(); e.Handled = true; };
        SourceInitialized += (_, _) =>
        {
            var handle = new WindowInteropHelper(this).Handle;
            SetWindowLongPtr(handle, -20, GetWindowLongPtr(handle, -20) | 0x08000000 | 0x00000080);
            HwndSource.FromHwnd(handle)?.AddHook(WindowMessage);
            if (settings.X is double x && settings.Y is double y) { Left = x; Top = y; KeepVisible(); }
            else PlaceAtCorner();
        };
        using var iconStream = Resource("icon.ico");
        tray = new Forms.NotifyIcon { Text = "陈震桌宠 · 右键设置", Icon = new System.Drawing.Icon(iconStream), Visible = true };
        tray.MouseUp += (_, _) => Dispatcher.Invoke(ShowMenu);
        Closed += (_, _) => { shuttingDown = true; Stop(); audio?.Dispose(); Save(); tray.Visible = false; tray.Dispose(); };
    }

    private nint WindowMessage(nint hwnd, int msg, nint wParam, nint lParam, ref bool handled)
    {
        if (msg == 0x0021) { handled = true; return 3; } // MA_NOACTIVATE, keep keyboard focus in the user's app.
        if (msg is 0x007E or 0x02E0) Dispatcher.BeginInvoke(() => { if (!shuttingDown) { CancelFoodDrag(); KeepVisible(); Save(); } });
        return 0;
    }
    private void PointerDown(object sender, MouseButtonEventArgs e)
    {
        var position = e.GetPosition(this);
        if (!AvatarRect.Contains(new ScenePoint(position.X, position.Y))) return;
        GetCursorPos(out initialMouse); initialLeft = Left; initialTop = Top; dragged = false; pointerDown = true;
        ((UIElement)sender).CaptureMouse(); e.Handled = true;
    }
    private void PointerMove(object sender, MouseEventArgs e)
    {
        if (!pointerDown || e.LeftButton != MouseButtonState.Pressed) return;
        GetCursorPos(out var now); var dpi = VisualTreeHelper.GetDpi(this);
        double dx = now.X - initialMouse.X, dy = now.Y - initialMouse.Y;
        if (Placement.IsDrag(dx, dy, dpi.DpiScaleX)) dragged = true;
        if (dragged) { Left = initialLeft + dx / dpi.DpiScaleX; Top = initialTop + dy / dpi.DpiScaleY; }
    }
    private void PointerUp(object sender, MouseButtonEventArgs e)
    {
        if (!pointerDown) return;
        pointerDown = false; ((UIElement)sender).ReleaseMouseCapture();
        if (dragged) { KeepVisible(); Save(); } else PlayNext();
        e.Handled = true;
    }
    private void PlayNext()
    {
        int id = bag.Next(clips.Select(x => x.id).ToArray());
        Play(clips.First(c => c.id == id));
        lastPortraitID = id;
    }
    private void Play(Clip clip)
    {
        lastPortraitID = null;
        Stop(); long token = generation;
        try
        {
            audio ??= new FastAudio(audioBytes);
            long ticket = audio.Play(clip.id,settings.Volume); current = ticket;
            caption.Text = clip.label; bubble.Visibility = Visibility.Visible;
            if (SystemParameters.ClientAreaAnimation)
                squash.BeginAnimation(ScaleTransform.ScaleYProperty,new DoubleAnimation(1,.88,TimeSpan.FromMilliseconds(150))
                    { AutoReverse = true, RepeatBehavior = RepeatBehavior.Forever });
            var timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(15) }; audioTimer=timer;
            long? drained = null;
            timer.Tick += async (_,_) =>
            {
                if(generation!=token || current!=ticket){timer.Stop();return;}
                try { audio.CheckStatus(); }
                catch(Exception e){timer.Stop();AudioFailure(e);return;}
                if(!audio.Finished(ticket))return;
                drained ??= System.Diagnostics.Stopwatch.GetTimestamp();
                if(System.Diagnostics.Stopwatch.GetElapsedTime(drained.Value).TotalMilliseconds<55)return;
                timer.Stop();current=null;audioTimer=null;
                if(activeAction!=null){if(visualDone)StopInteraction(false);return;}
                AnimateStop();
                await System.Threading.Tasks.Task.Delay(400);
                if(generation==token)bubble.Visibility=Visibility.Hidden;
            };
            timer.Start();
        }
        catch(Exception e){AudioFailure(e);}
    }
    private void AudioFailure(Exception e)
    {
        Stop();audio?.Dispose();audio=null;
        caption.Text="声音无法播放，请检查音频设备";bubble.Visibility=Visibility.Visible;Program.Log(e);
    }
    private void AnimateStop() { squash.BeginAnimation(ScaleTransform.ScaleYProperty, null); squash.ScaleY = 1; }
    private void Stop()
    { StopInteraction(true); }
    private void StopInteraction(bool cancelDrag)
    {
        interaction.Next(); audioTimer?.Stop(); audioTimer = null; current = null; audio?.Stop();
        CancelAction(); if (cancelDrag) CancelFoodDrag();
        AnimateStop(); bubble.Visibility = Visibility.Hidden;
    }
    private void SetPortraitAnchors(Portrait portrait)
    {
        manifest.anchors["mouth"] = portrait.mouth; manifest.anchors["head"] = portrait.head;
    }
    private void SetPortrait(Portrait portrait)
    {
        if (!portraitImages.TryGetValue(portrait.id, out var image)) return;
        Stop(); double right = Left + Width, bottom = Top + Height;
        settings.PortraitID = portrait.id; face.Source = image;
        ratio = (double)image.PixelHeight / image.PixelWidth;
        SetPortraitAnchors(portrait); SizeTo(settings.Size);
        Left = right - Width; Top = bottom - Height; KeepVisible(); Save();
    }
    private void SizeTo(double width) { Width = width; Height = (width - 16) * (956.0 / 1070.0) + 52 + 114 * width/260; }
    private void Save()
    {
        settings.X = Left; settings.Y = Top;
        try { settings.Save(settingsPath); } catch (Exception e) when (e is IOException or UnauthorizedAccessException) { Program.Log(e); }
    }
    private Forms.Screen CurrentScreen()
    {
        var handle = new WindowInteropHelper(this).Handle;
        return handle == 0 ? (Forms.Screen.PrimaryScreen ?? Forms.Screen.AllScreens[0]) : Forms.Screen.FromHandle(handle);
    }
    private void PlaceAtCorner()
    {
        var area = CurrentScreen().WorkingArea; var dpi = VisualTreeHelper.GetDpi(this);
        Left = area.Right / dpi.DpiScaleX - Width - 32; Top = area.Bottom / dpi.DpiScaleY - Height - 24;
        KeepVisible(); Save();
    }
    private void KeepVisible()
    {
        var area = CurrentScreen().WorkingArea; var dpi = VisualTreeHelper.GetDpi(this);
        (double x, double y) = Placement.Clamp(Left, Top, Width, Height,
            area.Left / dpi.DpiScaleX, area.Top / dpi.DpiScaleY, area.Width / dpi.DpiScaleX, area.Height / dpi.DpiScaleY);
        Left = x; Top = y;
    }
    private MenuItem Item(string title, Action action, bool? check = null)
    {
        var item = new MenuItem { Header = title };
        if (check.HasValue) { item.IsCheckable = true; item.IsChecked = check.Value; }
        item.Click += (_, _) => action(); return item;
    }
    private void ShowMenu()
    {
        var menu = new ContextMenu { Placement = System.Windows.Controls.Primitives.PlacementMode.MousePoint };
        menu.Items.Add(new MenuItem { Header = "陈震桌宠 · 6 句原声", IsEnabled = false });
        menu.Items.Add(new Separator());
        var choose = new MenuItem { Header = "挑一句" };
        foreach (var clip in clips) choose.Items.Add(Item(clip.label, () => Play(clip)));
        menu.Items.Add(choose);
        var portraitMenu = new MenuItem { Header = "更换人像" };
        foreach (var portrait in portraits) portraitMenu.Items.Add(Item(portrait.name, () => SetPortrait(portrait), portrait.id == settings.PortraitID));
        menu.Items.Add(portraitMenu);
        var volume = new MenuItem { Header = "音量" };
        foreach (int percent in new[] { 0, 25, 50, 65, 80, 100 })
            volume.Items.Add(Item(percent == 0 ? "静音" : percent + "%", () => { settings.Volume = percent / 100d; if (audio != null) audio.Volume = settings.Volume; Save(); }, Math.Abs(settings.Volume - percent / 100d) < .01));
        menu.Items.Add(volume);
        var size = new MenuItem { Header = "人物大小" };
        foreach (var entry in new[] { ("小", 190d), ("中", 260d), ("大", 340d) })
            size.Items.Add(Item(entry.Item1, () => { double right = Left + Width, bottom = Top + Height; settings.Size = entry.Item2;
                SizeTo(settings.Size); Left = right - Width; Top = bottom - Height; KeepVisible(); Save(); }, settings.Size == entry.Item2));
        menu.Items.Add(size); menu.Items.Add(Item("移回屏幕右下角", PlaceAtCorner));
        menu.Items.Add(new Separator()); menu.Items.Add(Item("退出桌宠", Close));
        menu.IsOpen = true;
    }

    [StructLayout(LayoutKind.Sequential)] private struct NativePoint { public int X; public int Y; }
    [DllImport("user32.dll")] private static extern bool GetCursorPos(out NativePoint point);
    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")] private static extern nint GetWindowLongPtr(nint hwnd, int index);
    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW")] private static extern nint SetWindowLongPtr(nint hwnd, int index, nint value);
}
