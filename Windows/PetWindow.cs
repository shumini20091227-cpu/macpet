using System.Diagnostics;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using Microsoft.Win32;
using Timer = System.Windows.Forms.Timer;

namespace MacPet;

internal sealed class PetWindow : Form
{
    private readonly Settings settings;
    private readonly ExpressionStore store;
    private readonly NotifyIcon tray;
    private readonly Timer frameTimer = new(), saveTimer = new(), visibilityTimer = new();
    private readonly Stopwatch clock = Stopwatch.StartNew();
    private Animation animation;
    private Expression selected;
    private Bitmap? surface;
    private ContextMenuStrip? menu;
    private bool resizing, editingGlints, locked, asleep, covered, modal, menuOpen;
    private bool lowPower = Native.LowPower;
    private int lastFrame = -1, resizeCorner = -1, glintSlot = -1;
    private Point mouseDown, originDown;
    private double sizeDown, phaseAnchor, timeAnchor;
    private bool dragged, cleaned;
    private PointF look, lookOffset;
    private double headTilt;
    private string? banner;
    private readonly Timer bannerTimer = new();
    private readonly Native.WinEventProc visibilityCallback;
    private readonly List<nint> hooks = [];
    private nint displayNotification, energyNotification;
    internal int RenderCount { get; private set; }
    internal bool FrameTimerRunning => frameTimer.Enabled;
    internal string SelectedId => selected.Id;
    private float ScaleFactor => DeviceDpi / 96f;
    private int PaddingPixels => resizing ? (int)Math.Round(22 * ScaleFactor) : 0;
    private int PetPixels => (int)Math.Round(settings.PetSize * ScaleFactor);
    private double Phase => phaseAnchor + (clock.Elapsed.TotalSeconds - timeAnchor) * settings.Speed;
    private bool Legacy => selected.Id == ExpressionStore.Legacy;
    private bool CanAnimate => Visible && !locked && !asleep && !covered && !modal && !menuOpen && !editingGlints;
    protected override bool ShowWithoutActivation => true;
    protected override CreateParams CreateParams
    {
        get { var value = base.CreateParams; value.ExStyle |= 0x80000 | 0x80; return value; }
    }

    internal PetWindow(string root)
    {
        settings = Settings.Load(root);
        store = new(root, settings);
        store.Seed();
        selected = store.Initial();
        try { animation = store.Load(selected); }
        catch { selected = store.Entries()[0]; animation = store.Load(selected); }
        settings.SelectedExpression = selected.Id;
        Text = "MacPet";
        Icon = Assets.Icon();
        FormBorderStyle = FormBorderStyle.None;
        ShowInTaskbar = false;
        TopMost = true;
        StartPosition = FormStartPosition.Manual;
        AutoScaleMode = AutoScaleMode.None;
        SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint, true);
        tray = new NotifyIcon { Icon = Icon, Text = "MacPet", Visible = true };
        tray.DoubleClick += (_, _) => ShowPet();
        tray.MouseUp += (_, e) =>
        {
            if (e.Button == MouseButtons.Right)
            {
                menu?.Dispose(); menu = BuildMenu(); tray.ContextMenuStrip = menu;
                menu.Show(Cursor.Position);
            }
        };
        frameTimer.Tick += (_, _) => { frameTimer.Stop(); RenderFrame(); };
        saveTimer.Interval = 400;
        saveTimer.Tick += (_, _) => { saveTimer.Stop(); Persist(); };
        bannerTimer.Interval = 2400;
        bannerTimer.Tick += (_, _) => { bannerTimer.Stop(); banner = null; RenderFrame(true); };
        visibilityTimer.Interval = 100;
        visibilityTimer.Tick += (_, _) =>
        {
            visibilityTimer.Stop();
            if (IsDisposed || !Visible) return;
            bool next = Native.IsFullyCovered(Handle, Bounds);
            if (next != covered) { covered = next; ResumeAnimation(); }
        };
        visibilityCallback = (_, _, hwnd, objectId, _, _, _) =>
        {
            if (IsDisposed || !IsHandleCreated || hwnd == Handle || objectId != 0) return;
            try { BeginInvoke(() => { if (!IsDisposed && Visible) { visibilityTimer.Stop(); visibilityTimer.Start(); } }); }
            catch (InvalidOperationException) { }
        };
        SystemEvents.SessionSwitch += SessionChanged;
        SystemEvents.PowerModeChanged += PowerChanged;
        LayoutPet();
        Location = new(settings.X ?? Screen.PrimaryScreen!.WorkingArea.Left + 48,
            settings.Y ?? Screen.PrimaryScreen!.WorkingArea.Bottom - Height - 48);
        EnsureOnScreen();
    }

    protected override void OnHandleCreated(EventArgs e)
    {
        base.OnHandleCreated(e);
        var display = Native.DisplayState; var energy = Native.EnergySaver;
        displayNotification = Native.RegisterPowerSettingNotification(Handle, ref display, 0);
        energyNotification = Native.RegisterPowerSettingNotification(Handle, ref energy, 0);
        hooks.Add(Native.SetWinEventHook(3, 3, 0, visibilityCallback, 0, 0, 0));
        hooks.Add(Native.SetWinEventHook(0x8002, 0x8003, 0, visibilityCallback, 0, 0, 0));
        hooks.Add(Native.SetWinEventHook(0x800B, 0x800B, 0, visibilityCallback, 0, 0, 0));
    }
    protected override void OnShown(EventArgs e)
    {
        base.OnShown(e);
        LayoutPet(); EnsureOnScreen();
        if (settings.Hidden) HidePet(); else ResumeAnimation();
    }
    protected override void OnPaintBackground(PaintEventArgs e) { }
    protected override void OnPaint(PaintEventArgs e) { }
    protected override void OnDpiChanged(DpiChangedEventArgs e)
    {
        base.OnDpiChanged(e); LayoutPet(); EnsureOnScreen(); RenderFrame(true);
    }
    protected override void WndProc(ref Message m)
    {
        if (m.Msg == Native.WmMouseActivate) { m.Result = Native.MaNoActivate; return; }
        if (m.Msg == Native.WmPowerBroadcast && m.WParam == Native.PowerSettingChange && m.LParam != 0)
        {
            var guid = Marshal.PtrToStructure<Guid>(m.LParam);
            int length = Marshal.ReadInt32(m.LParam, 16);
            if (length >= 4)
            {
                int value = Marshal.ReadInt32(m.LParam, 20);
                if (guid == Native.DisplayState) asleep = value == 0;
                if (guid == Native.EnergySaver) lowPower = value != 0;
                ResumeAnimation();
            }
        }
        base.WndProc(ref m);
    }
    private void SessionChanged(object sender, SessionSwitchEventArgs e)
    {
        if (IsDisposed || !IsHandleCreated) return;
        try { BeginInvoke(() => { locked = e.Reason == SessionSwitchReason.SessionLock || (locked && e.Reason != SessionSwitchReason.SessionUnlock); ResumeAnimation(); }); }
        catch (InvalidOperationException) { }
    }
    private void PowerChanged(object sender, PowerModeChangedEventArgs e)
    {
        if (IsDisposed || !IsHandleCreated) return;
        try { BeginInvoke(() => { asleep = e.Mode == PowerModes.Suspend; lowPower = Native.LowPower; ResumeAnimation(); }); }
        catch (InvalidOperationException) { }
    }

    private void LayoutPet()
    {
        int length = PetPixels + PaddingPixels * 2;
        ClientSize = new(length, length);
    }
    private void EnsureOnScreen()
    {
        if (!Screen.AllScreens.Any(s => s.WorkingArea.IntersectsWith(Bounds)))
            Location = new(Screen.PrimaryScreen!.WorkingArea.Left + 48, Screen.PrimaryScreen!.WorkingArea.Top + 48);
    }
    private RectangleF Fitted()
    {
        var image = animation.Frames[Math.Max(0, lastFrame) % animation.Frames.Count];
        float factor = Math.Min((float)PetPixels / image.Width, (float)PetPixels / image.Height);
        return new(PaddingPixels + (PetPixels - image.Width * factor) / 2,
            PaddingPixels + (PetPixels - image.Height * factor) / 2, image.Width * factor, image.Height * factor);
    }
    private void Schedule()
    {
        frameTimer.Stop();
        if (!CanAnimate) return;
        double fps = lowPower ? 6 : settings.EnergySaving ? 12 : 30;
        double? delay = Legacy ? 1 / fps : animation.NextDelay(Phase, settings.Speed, fps);
        if (delay == null) return;
        frameTimer.Interval = Math.Max(1, (int)Math.Ceiling(delay.Value * 1000));
        frameTimer.Start();
    }
    private void ResumeAnimation()
    {
        frameTimer.Stop();
        if (CanAnimate) RenderFrame(true);
    }
    internal void RenderFrame(bool force = false)
    {
        if (IsDisposed || !IsHandleCreated) return;
        frameTimer.Stop();
        int index = animation.Index(Phase);
        if (!force && !Legacy && lastFrame == index) { Schedule(); return; }
        lastFrame = index;
        var next = new Bitmap(Width, Height, PixelFormat.Format32bppPArgb);
        using (var graphics = Graphics.FromImage(next))
        {
            graphics.Clear(Color.Transparent);
            graphics.SmoothingMode = SmoothingMode.AntiAlias;
            graphics.InterpolationMode = InterpolationMode.HighQualityBicubic;
            graphics.PixelOffsetMode = PixelOffsetMode.HighQuality;
            var state = graphics.Save();
            if (Legacy && !editingGlints)
            {
                var cursor = Cursor.Position;
                float range = Math.Max(1, PetPixels * 1.8f), weight = resizing ? .25f : 1;
                float x = (float)Math.Tanh(Math.Clamp((cursor.X - (Left + Width / 2f)) / range, -1, 1) * 1.25) * weight;
                float y = (float)Math.Tanh(Math.Clamp(((Top + PaddingPixels + PetPixels * .42f) - cursor.Y) / range, -1, 1) * 1.25) * weight;
                look = new(look.X + (x - look.X) * .32f, look.Y + (y - look.Y) * .32f);
                lookOffset = new(look.X * 16 * ScaleFactor, -look.Y * 12 * ScaleFactor);
                headTilt = look.X * 14;
                float wave = (float)Math.Sin(2 * Math.PI * clock.Elapsed.TotalSeconds / 2.6);
                using var matrix = new Matrix();
                matrix.Translate(-Width / 2f, -PaddingPixels - PetPixels, MatrixOrder.Append);
                matrix.Scale(1 + .012f * wave, 1 + .045f * wave, MatrixOrder.Append);
                matrix.Translate(Width / 2f, PaddingPixels + PetPixels, MatrixOrder.Append);
                matrix.RotateAt((float)(headTilt + 1.1 * Math.Sin(clock.Elapsed.TotalSeconds * 1.15)),
                    new(Width * .5f, PaddingPixels + PetPixels * .6f), MatrixOrder.Append);
                matrix.Translate(lookOffset.X, lookOffset.Y - wave * 2.4f * ScaleFactor, MatrixOrder.Append);
                graphics.Transform = matrix;
            }
            graphics.DrawImage(animation.Frames[index], Fitted());
            if (Legacy) DrawGlints(graphics);
            graphics.Restore(state);
            if (resizing) DrawResizeChrome(graphics);
            if (banner != null)
            {
                using var font = new Font("Microsoft YaHei UI", Math.Max(8, (float)settings.PetSize * .055f));
                var textSize = graphics.MeasureString(banner, font);
                var rect = new RectangleF((Width - textSize.Width) / 2 - 7, PaddingPixels + PetPixels * .07f, textSize.Width + 14, textSize.Height + 7);
                using var background = new SolidBrush(Color.FromArgb(170, 0, 0, 0));
                graphics.FillRectangle(background, rect);
                graphics.DrawString(banner, font, Brushes.White, rect.X + 7, rect.Y + 3);
            }
        }
        try { Native.Present(Handle, next, Location); }
        catch { next.Dispose(); throw; }
        surface?.Dispose(); surface = next;
        RenderCount++;
        Schedule();
    }
    private PointF GlintCenter(PointF unit)
    {
        var fitted = Fitted(); return new(fitted.X + unit.X * fitted.Width, fitted.Y + unit.Y * fitted.Height);
    }
    private void DrawGlints(Graphics graphics)
    {
        var fitted = Fitted();
        foreach (var unit in new[] { settings.LeftGlint, settings.RightGlint })
        {
            var center = GlintCenter(unit);
            float socketWidth = fitted.Width * .108f, socketHeight = fitted.Height * .050f;
            float dx = -socketWidth * .14f + look.X * socketWidth * .3f;
            float dy = socketHeight * .12f - look.Y * socketHeight * .34f;
            using var soft = new SolidBrush(Color.FromArgb(56, Color.White));
            graphics.FillEllipse(soft, center.X + dx * .35f - socketWidth * .21f, center.Y + dy * .35f - socketHeight * .275f, socketWidth * .42f, socketHeight * .55f);
            float size = Math.Max(3.2f * ScaleFactor, PetPixels * .016f);
            graphics.FillEllipse(Brushes.White, center.X + dx - size / 2, center.Y + dy - size / 2, size, size);
            if (editingGlints)
            {
                using var pen = new Pen(Color.White, 1.6f * ScaleFactor);
                float handle = 28 * ScaleFactor;
                graphics.DrawEllipse(pen, center.X - handle / 2, center.Y - handle / 2, handle, handle);
            }
        }
    }
    private PointF[] Corners() => [new(PaddingPixels, PaddingPixels), new(PaddingPixels + PetPixels, PaddingPixels),
        new(PaddingPixels, PaddingPixels + PetPixels), new(PaddingPixels + PetPixels, PaddingPixels + PetPixels)];
    private void DrawResizeChrome(Graphics graphics)
    {
        using var pen = new Pen(Color.White, 1.6f * ScaleFactor) { DashPattern = [6, 4] };
        graphics.DrawRectangle(pen, PaddingPixels, PaddingPixels, PetPixels, PetPixels);
        foreach (var corner in Corners())
        {
            float size = 12 * ScaleFactor;
            graphics.FillEllipse(Brushes.White, corner.X - size / 2, corner.Y - size / 2, size, size);
            graphics.DrawEllipse(Pens.Black, corner.X - size / 2, corner.Y - size / 2, size, size);
        }
    }
    private static double Distance(PointF a, PointF b) => Math.Sqrt(Math.Pow(a.X - b.X, 2) + Math.Pow(a.Y - b.Y, 2));
    protected override void OnMouseDown(MouseEventArgs e)
    {
        base.OnMouseDown(e);
        if (e.Button != MouseButtons.Left) return;
        mouseDown = Cursor.Position; originDown = Location; sizeDown = settings.PetSize; dragged = false;
        resizeCorner = resizing ? Array.FindIndex(Corners(), p => Distance(p, e.Location) <= 28 * ScaleFactor) : -1;
        glintSlot = editingGlints ? Array.FindIndex(new[] { GlintCenter(settings.LeftGlint), GlintCenter(settings.RightGlint) }, p => Distance(p, e.Location) <= 28 * ScaleFactor) : -1;
        Capture = true;
    }
    protected override void OnMouseMove(MouseEventArgs e)
    {
        base.OnMouseMove(e);
        if (!Capture || (MouseButtons & MouseButtons.Left) == 0) return;
        var cursor = Cursor.Position; int dx = cursor.X - mouseDown.X, dy = cursor.Y - mouseDown.Y;
        if (glintSlot >= 0)
        {
            var fitted = Fitted();
            var unit = Settings.ClampGlint(new((e.X - fitted.X) / fitted.Width, (e.Y - fitted.Y) / fitted.Height), new(.5f, .5f));
            if (glintSlot == 0) settings.LeftGlint = unit; else settings.RightGlint = unit;
            dragged = true; RenderFrame(true); return;
        }
        if (resizeCorner >= 0)
        {
            int horizontal = resizeCorner % 2 == 0 ? -dx : dx;
            int vertical = resizeCorner < 2 ? -dy : dy;
            SetPetSize(sizeDown + (horizontal + vertical) / ScaleFactor);
            dragged = true; return;
        }
        if (editingGlints) return;
        if (Math.Sqrt(dx * dx + dy * dy) > 5 * ScaleFactor)
        {
            dragged = true; Location = new(originDown.X + dx, originDown.Y + dy); RenderFrame(true);
        }
    }
    protected override void OnMouseUp(MouseEventArgs e)
    {
        base.OnMouseUp(e); Capture = false;
        if (e.Button == MouseButtons.Right) { OpenContextMenu(Cursor.Position); return; }
        if (e.Button != MouseButtons.Left) return;
        if (dragged) Persist();
        else if (!resizing && !editingGlints && e.Clicks == 1) Try(() => Process.Start(new ProcessStartInfo("https://chatgpt.com") { UseShellExecute = true }));
        resizeCorner = glintSlot = -1;
    }
    protected override void OnMouseWheel(MouseEventArgs e)
    {
        base.OnMouseWheel(e); if (resizing) SetPetSize(settings.PetSize + e.Delta / 15.0);
    }
    private void SetPetSize(double size)
    {
        float midX = Left + Width / 2f; int bottom = Bottom - PaddingPixels;
        settings.PetSize = Math.Clamp(size, 100, 560); LayoutPet();
        Location = new((int)Math.Round(midX - Width / 2f), bottom - Height + PaddingPixels);
        RenderFrame(true); saveTimer.Stop(); saveTimer.Start();
    }
    private void ToggleResize()
    {
        int oldPadding = PaddingPixels; int footBottom = Bottom - oldPadding; float midX = Left + Width / 2f;
        editingGlints = false; resizing = !resizing; LayoutPet();
        Location = new((int)Math.Round(midX - Width / 2f), footBottom - Height + PaddingPixels);
        Cursor = resizing ? Cursors.SizeAll : Cursors.Default; RenderFrame(true);
    }
    private void ToggleGlints()
    {
        if (resizing) ToggleResize();
        editingGlints = !editingGlints; look = lookOffset = PointF.Empty;
        Cursor = editingGlints ? Cursors.Hand : Cursors.Default; RenderFrame(true);
    }
    private void Select(Expression entry)
    {
        var next = store.Load(entry);
        animation.Dispose(); animation = next; selected = entry;
        phaseAnchor = 0; timeAnchor = clock.Elapsed.TotalSeconds; lastFrame = -1;
        settings.SelectedExpression = entry.Id;
        settings.LeftGlint = new(.372f, .542f); settings.RightGlint = new(.615f, .536f);
        editingGlints = false; Persist(); RenderFrame(true);
    }
    private void SetSpeed(double speed)
    {
        phaseAnchor = Phase; timeAnchor = clock.Elapsed.TotalSeconds;
        settings.Speed = speed; Persist(); ShowBanner($"动画速度 {speed}×"); RenderFrame(true);
    }
    private void ShowBanner(string text) { banner = text; bannerTimer.Stop(); bannerTimer.Start(); RenderFrame(true); }
    private void Try(Action action)
    {
        try { action(); }
        catch (Exception error) when (error is not OutOfMemoryException and not StackOverflowException)
        { MessageBox.Show(error.Message, "MacPet", MessageBoxButtons.OK, MessageBoxIcon.Warning); }
    }
    private void WithDialog(Action action)
    {
        modal = true; frameTimer.Stop();
        try { action(); } finally { modal = false; ResumeAnimation(); }
    }
    private void Import()
    {
        WithDialog(() =>
        {
            using var dialog = new OpenFileDialog { Title = "导入表情", Filter = "GIF 动画或 PNG|*.gif;*.png", Multiselect = true };
            if (dialog.ShowDialog() != DialogResult.OK) return;
            List<string> failures = [];
            foreach (var path in dialog.FileNames)
            {
                try { Select(store.Import(path)); } catch { failures.Add(Path.GetFileName(path)); }
            }
            if (failures.Count > 0) MessageBox.Show("部分表情未能导入：\n" + string.Join("、", failures), "MacPet");
        });
    }
    private void Remove(IEnumerable<Expression> entries)
    {
        var selectedEntries = entries.ToList(); var failures = store.Remove(selectedEntries);
        if (!store.Entries().Any(e => e.Id == selected.Id))
        {
            var remaining = store.Entries();
            try { Select(remaining.FirstOrDefault(e => e.Id != ExpressionStore.Legacy) ?? remaining[0]); }
            catch { Select(remaining[0]); }
        }
        if (failures.Count > 0) MessageBox.Show("部分表情未能删除：\n" + string.Join("、", failures), "MacPet");
        ShowBanner($"已删除 {selectedEntries.Count - failures.Count} 个表情");
    }
    private void BatchDelete()
    {
        WithDialog(() =>
        {
            using var picker = new DeletionPicker(store.Entries().Where(e => e.Id != ExpressionStore.Legacy).ToList(), Icon!);
            if (picker.ShowDialog() == DialogResult.OK) Remove(picker.SelectedEntries);
        });
    }
    private void ReplaceCharacter()
    {
        WithDialog(() =>
        {
            using var dialog = new OpenFileDialog { Title = "更换形象", Filter = "PNG 图片|*.png" };
            if (dialog.ShowDialog() != DialogResult.OK) return;
            using (Animation.FromFile(dialog.FileName)) { }
            Directory.CreateDirectory(store.Root);
            File.Copy(dialog.FileName, store.CustomPath + ".tmp", true);
            File.Move(store.CustomPath + ".tmp", store.CustomPath, true);
            Select(store.Entries()[0]);
        });
    }
    private void OpenContextMenu(Point point)
    {
        menu?.Dispose(); menu = BuildMenu(); menu.Show(point);
    }
    internal ContextMenuStrip BuildMenu()
    {
        var result = new ContextMenuStrip { ShowImageMargin = false };
        result.Opened += (_, _) => { menuOpen = true; frameTimer.Stop(); };
        result.Closed += (_, _) => { menuOpen = false; ResumeAnimation(); };
        void Add(ToolStripItemCollection target, string text, Action action, bool enabled = true, bool check = false)
        {
            var item = new ToolStripMenuItem(text) { Enabled = enabled, Checked = check };
            item.Click += (_, _) => { result.Close(); Try(action); }; target.Add(item);
        }
        var expressions = new ToolStripMenuItem("切换表情");
        foreach (var entry in store.Entries())
        {
            var row = new ExpressionRow(entry.Name, entry.Id == selected.Id, entry.Id != ExpressionStore.Legacy,
                () => { result.Close(); Try(() => Select(entry)); },
                () => { result.Close(); Try(() => Remove([entry])); });
            expressions.DropDownItems.Add(new ToolStripControlHost(row) { AutoSize = false, Size = row.Size, Margin = System.Windows.Forms.Padding.Empty, Padding = System.Windows.Forms.Padding.Empty });
        }
        expressions.DropDownItems.Add(new ToolStripSeparator());
        Add(expressions.DropDownItems, "导入表情…", Import);
        Add(expressions.DropDownItems, "批量删除…", BatchDelete, store.Entries().Count > 1);
        result.Items.Add(expressions);
        var speeds = new ToolStripMenuItem("动画速度");
        foreach (var (label, speed) in new[] { ("很慢（0.25×）", .25), ("舒缓（0.5×，默认）", .5), ("稍慢（0.75×）", .75), ("原速（1×）", 1.0) })
            Add(speeds.DropDownItems, label, () => SetSpeed(speed), check: speed == settings.Speed);
        result.Items.Add(speeds);
        Add(result.Items, "省电模式（推荐）", () => { settings.EnergySaving = !settings.EnergySaving; Persist(); ResumeAnimation(); }, check: settings.EnergySaving);
        result.Items.Add(new ToolStripSeparator());
        Add(result.Items, resizing ? "完成调整" : "调整大小", ToggleResize);
        Add(result.Items, editingGlints ? "完成高光" : "调整高光", ToggleGlints, Legacy);
        if (editingGlints) Add(result.Items, "恢复默认高光", () => { settings.LeftGlint = new(.372f, .542f); settings.RightGlint = new(.615f, .536f); Persist(); RenderFrame(true); });
        Add(result.Items, "更换形象", ReplaceCharacter);
        Add(result.Items, "恢复默认形象", () => { if (File.Exists(store.CustomPath)) File.Delete(store.CustomPath); Select(store.Entries()[0]); }, File.Exists(store.CustomPath));
        Add(result.Items, "刷新", () => { var next = store.Load(selected); animation.Dispose(); animation = next; phaseAnchor = 0; timeAnchor = clock.Elapsed.TotalSeconds; lastFrame = -1; RenderFrame(true); });
        Add(result.Items, Visible ? "隐藏" : "显示", () => { if (Visible) HidePet(); else ShowPet(); });
        Add(result.Items, "退出", Close);
        return result;
    }
    internal void HidePet() { settings.Hidden = true; frameTimer.Stop(); visibilityTimer.Stop(); Hide(); Persist(); }
    internal void ShowPet() { settings.Hidden = false; covered = false; Show(); EnsureOnScreen(); Persist(); ResumeAnimation(); }
    internal void SavePreview(string path) { RenderFrame(true); surface!.Save(path, ImageFormat.Png); }
    private void Persist() { settings.X = Left; settings.Y = Top; settings.Save(store.Root); }
    protected override void Dispose(bool disposing)
    {
        if (disposing && !cleaned)
        {
            cleaned = true;
            frameTimer.Stop(); saveTimer.Stop(); visibilityTimer.Stop(); bannerTimer.Stop();
            SystemEvents.SessionSwitch -= SessionChanged; SystemEvents.PowerModeChanged -= PowerChanged;
            foreach (var hook in hooks.Where(h => h != 0)) Native.UnhookWinEvent(hook);
            if (displayNotification != 0) Native.UnregisterPowerSettingNotification(displayNotification);
            if (energyNotification != 0) Native.UnregisterPowerSettingNotification(energyNotification);
            frameTimer.Dispose(); saveTimer.Dispose(); visibilityTimer.Dispose(); bannerTimer.Dispose();
            tray.Visible = false; tray.Dispose(); menu?.Dispose(); animation.Dispose(); surface?.Dispose();
        }
        base.Dispose(disposing);
    }
    protected override void OnFormClosing(FormClosingEventArgs e) { Persist(); base.OnFormClosing(e); }
}
