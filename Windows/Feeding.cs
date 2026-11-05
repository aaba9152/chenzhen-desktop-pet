using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Data;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;

namespace ChenzhenPet;

public sealed partial class PetWindow
{
    private ActionLibrary manifest = null!;
    private readonly ActionScene actionScene = new();
    private readonly Canvas toolbar = new();
    private readonly List<Button> foodButtons = new();
    private FeedingAction? activeAction;
    private bool visualDone;
    private DispatcherTimer? actionTimer, ghostTimer;
    private long actionStart;
    private ScenePoint normalizedStart;
    private Window? ghost;
    private int? foodIndex;
    private bool foodPointerDown, foodDragged;
    private NativePoint foodStart;
    private double Unit => Width/260;
    private SceneRect AvatarRect => Placement.AvatarRect(Width, Height, ratio);

    private void InitializeFeeding(Grid root)
    {
        using (var stream = Resource("actions.json")) manifest = JsonSerializer.Deserialize<ActionLibrary>(stream) ?? throw new InvalidOperationException("Missing actions");
        manifest.Validate();
        foreach (var name in manifest.actions.SelectMany(a => a.layers.Select(l => l.sprite).Append(a.icon)).Where(n => n != "stream").Distinct())
        {
            var bitmap = new BitmapImage(); using var stream = Resource("Actions." + name + ".png");
            bitmap.BeginInit(); bitmap.CacheOption = BitmapCacheOption.OnLoad; bitmap.StreamSource = stream; bitmap.EndInit(); bitmap.Freeze();
            actionScene.Sprites[name] = bitmap;
        }
        root.Children.Insert(1, actionScene);
        toolbar.VerticalAlignment = VerticalAlignment.Bottom; root.Children.Add(toolbar);
        for (int i = 0; i < manifest.actions.Length; i++)
        {
            int index = i; var action = manifest.actions[i];
            var image = new Image { Source = actionScene.Sprites[action.icon], RenderTransformOrigin = new Point(.5,.5), RenderTransform = new RotateTransform(action.iconRotation), IsHitTestVisible = false };
            var border = new FrameworkElementFactory(typeof(Border));
            border.SetValue(Border.CornerRadiusProperty, new CornerRadius(8));
            border.SetValue(Border.BorderBrushProperty, new SolidColorBrush(Color.FromRgb(71,41,26)));
            border.SetValue(Border.BorderThicknessProperty, new Thickness(1.8));
            border.SetValue(Border.BackgroundProperty, new SolidColorBrush(Color.FromArgb(250,255,245,219)));
            var presenter = new FrameworkElementFactory(typeof(ContentPresenter));
            presenter.SetValue(FrameworkElement.MarginProperty, new Thickness(3)); border.AppendChild(presenter);
            var button = new Button { Content = image, ToolTip = action.title, Focusable = false, IsTabStop = false,
                Cursor = Cursors.Hand, Template = new ControlTemplate(typeof(Button)) { VisualTree = border } };
            System.Windows.Automation.AutomationProperties.SetName(button, "投喂：" + action.title);
            button.PreviewMouseLeftButtonDown += (_, e) =>
            {
                foodPointerDown = true; foodDragged = false; foodIndex = index;
                GetCursorPos(out foodStart); button.CaptureMouse(); e.Handled = true;
            };
            button.PreviewMouseMove += (_, e) =>
            {
                if (!foodPointerDown || foodIndex != index) return;
                GetCursorPos(out var now);
                if (!foodDragged && Placement.IsDrag(now.X-foodStart.X, now.Y-foodStart.Y, VisualTreeHelper.GetDpi(this).DpiScaleX))
                { foodDragged = true; BeginGhost(index); }
                if (foodDragged) MoveGhost(now);
                e.Handled = true;
            };
            button.PreviewMouseLeftButtonUp += (_, e) =>
            {
                if (!foodPointerDown || foodIndex != index) return;
                foodPointerDown = false; button.ReleaseMouseCapture();
                if (foodDragged) EndFoodDrag(index); else { foodIndex = null; StartAction(action); }
                foodDragged = false; e.Handled = true;
            };
            button.LostMouseCapture += (_, _) => { if (foodPointerDown) CancelFoodDrag(); };
            // UI Automation's Invoke action uses Click rather than pointer events.
            button.Click += (_, _) => { if (!foodPointerDown) StartAction(action); };
            foodButtons.Add(button); toolbar.Children.Add(button);
        }
        SizeChanged += (_, _) => LayoutFeeding(); LayoutFeeding();
    }
    private void LayoutFeeding()
    {
        face.Margin = new Thickness(8,44+70*Unit,8,8+44*Unit);
        bubble.Width = Width * .76; bubble.Height = 56 * Unit; bubble.Margin = new Thickness(0, 42 * Unit, 0, 0);
        toolbar.Height = 48*Unit;
        for (int i = 0; i < foodButtons.Count; i++)
        {
            var button = foodButtons[i]; button.Width = button.Height = 44*Unit;
            Canvas.SetLeft(button,(Width-194*Unit)/2+i*50*Unit); Canvas.SetTop(button,2*Unit);
        }
        if (activeAction != null) RenderAction(Stopwatch.GetElapsedTime(actionStart).TotalSeconds);
    }
    private ScenePoint ButtonCenter(int index) => new((Width-194*Unit)/2+index*50*Unit+22*Unit,Height-24*Unit);
    private void StartAction(FeedingAction next, ScenePoint? from = null)
    {
        var start = from ?? ButtonCenter(Array.FindIndex(manifest.actions,a => a.id == next.id));
        int id = FeedingReply.Select(next.id, lastPortraitID, manifest.responses[Random.Shared.Next(manifest.responses.Length)]);
        lastPortraitID = null;
        var response = clips.First(c => c.id == id);
        Play(response); activeAction = next; visualDone = false;
        normalizedStart = new(start.x/Width,start.y/Height);
        caption.Text = response.label; bubble.Visibility = Visibility.Visible;
        actionStart = Stopwatch.GetTimestamp(); RenderAction(0);
        actionTimer = new DispatcherTimer(DispatcherPriority.Render) { Interval = TimeSpan.FromSeconds(1d/manifest.fps) };
        actionTimer.Tick += (_, _) =>
        {
            if (activeAction == null) return;
            double time = Stopwatch.GetElapsedTime(actionStart).TotalSeconds;
            if (time >= activeAction.duration)
            {
                actionTimer?.Stop(); actionTimer = null; visualDone = true;
                actionScene.Poses = []; actionScene.InvalidateVisual(); AnimateStop();
                if (current == null) StopInteraction(false);
            }
            else RenderAction(time);
        };
        actionTimer.Start();
    }
    private void RenderAction(double time)
    {
        if (activeAction == null) return;
        squash.BeginAnimation(ScaleTransform.ScaleYProperty,null);
        squash.ScaleY = SystemParameters.ClientAreaAnimation ? ActionSampler.Squash(time,activeAction.duration) : 1;
        actionScene.Poses = ActionSampler.Sample(activeAction,time,manifest,AvatarRect,
            new ScenePoint(normalizedStart.x*Width, normalizedStart.y*Height),Unit,squash.ScaleY);
        actionScene.InvalidateVisual();
    }
    private void CancelAction()
    {
        actionTimer?.Stop(); actionTimer = null; activeAction = null; visualDone = false;
        actionScene.Poses = []; actionScene.InvalidateVisual();
    }
    private void BeginGhost(int index)
    {
        CloseGhost();
        var a = manifest.actions[index]; double side = 48*Unit;
        var scene = new ActionScene { Sprites = actionScene.Sprites,
            Poses = [new SpritePose(a.icon,new(side/2,side/2),side,side,a.iconRotation,1)] };
        ghost = new Window { Width = side, Height = side, WindowStyle = WindowStyle.None, ResizeMode = ResizeMode.NoResize,
            AllowsTransparency = true, Background = Brushes.Transparent, Topmost = true, ShowActivated = false, ShowInTaskbar = false,
            Focusable = false, IsHitTestVisible = false, Content = scene };
        GetCursorPos(out var initial); var initialDpi = VisualTreeHelper.GetDpi(this);
        ghost.Left = initial.X/initialDpi.DpiScaleX-side/2; ghost.Top = initial.Y/initialDpi.DpiScaleY-side/2;
        ghost.SourceInitialized += (_, _) =>
        {
            var h = new WindowInteropHelper(ghost).Handle;
            SetWindowLongPtr(h,-20,GetWindowLongPtr(h,-20)|0x08000000|0x00000080|0x00000020);
        };
        ghost.Show();
    }
    private ScenePoint CursorLocal()
    {
        GetCursorPos(out var p); var point = PointFromScreen(new Point(p.X,p.Y)); return new(point.X,point.Y);
    }
    private void MoveGhost(NativePoint p)
    {
        if (ghost == null) return;
        var dpi = VisualTreeHelper.GetDpi(ghost);
        SetWindowPos(new WindowInteropHelper(ghost).Handle,0,p.X-(int)(ghost.Width*dpi.DpiScaleX/2),p.Y-(int)(ghost.Height*dpi.DpiScaleY/2),0,0,0x15);
        var r = AvatarRect;
        actionScene.Target = r.Contains(CursorLocal()) ? new Rect(r.x,r.y,r.width,r.height) : null;
        actionScene.InvalidateVisual();
    }
    private void EndFoodDrag(int index)
    {
        foodIndex = null; actionScene.Target = null; actionScene.InvalidateVisual();
        var p = CursorLocal();
        if (AvatarRect.Contains(p)) { CloseGhost(); StartAction(manifest.actions[index],p); return; }
        if (ghost == null) return;
        var returning = ghost; GetCursorPos(out var cursor);
        var center = ButtonCenter(index); var dest = PointToScreen(new Point(center.x,center.y));
        long start = Stopwatch.GetTimestamp();
        var timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1d/60) }; ghostTimer = timer;
        timer.Tick += (_, _) =>
        {
            if (ghost != returning) { timer.Stop(); return; }
            double t = Math.Min(1,Stopwatch.GetElapsedTime(start).TotalSeconds/.18);
            MoveGhost(new NativePoint { X = (int)(cursor.X+(dest.X-cursor.X)*t), Y = (int)(cursor.Y+(dest.Y-cursor.Y)*t) });
            actionScene.Target = null;
            if (t >= 1) CloseGhost();
        };
        timer.Start();
    }
    private void CloseGhost() { ghostTimer?.Stop(); ghostTimer = null; ghost?.Close(); ghost = null; }
    private void CancelFoodDrag()
    {
        foodPointerDown = false; foodDragged = false; foodIndex = null;
        foreach (var button in foodButtons) if (button.IsMouseCaptured) button.ReleaseMouseCapture();
        CloseGhost(); actionScene.Target = null; actionScene.InvalidateVisual();
    }
    [DllImport("user32.dll")] private static extern bool SetWindowPos(nint hwnd,nint insertAfter,int x,int y,int cx,int cy,uint flags);
}
