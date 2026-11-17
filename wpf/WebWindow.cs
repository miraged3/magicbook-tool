using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.IO;
using System.Threading;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Shapes;
using IconPath = System.Windows.Shapes.Path;
using System.Windows.Shell;
using System.Windows.Threading;
using Forms = System.Windows.Forms;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.Wpf;

namespace HonorHardware
{
    public sealed class WebWindow : Window
    {
        readonly IBackend backend;
        readonly bool demo;
        readonly AppPreferences preferences;
        readonly WebView2 view = new WebView2();
        readonly JavaScriptSerializer json = new JavaScriptSerializer();
        readonly SemaphoreSlim hardwareGate = new SemaphoreSlim(1);
        readonly DispatcherTimer refreshTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(5) };
        bool closed;
        bool exitRequested;
        Forms.NotifyIcon tray;
        Forms.ContextMenuStrip trayMenu;
        System.Drawing.Icon trayIcon;
        readonly Grid caption = new Grid { Height = 36 };
        readonly TextBlock captionTitle = new TextBlock
        {
            Text = "荣耀硬件助手",
            FontSize = 12,
            Margin = new Thickness(14, 0, 0, 0),
            VerticalAlignment = VerticalAlignment.Center,
            IsHitTestVisible = false
        };
        readonly Button minimizeButton;
        readonly Button closeButton;
        const string Origin = "https://honor.local/";

        internal WebWindow(bool demoMode, AppPreferences preferences)
        {
            demo = demoMode;
            this.preferences = preferences;
            backend = demo ? (IBackend)new DemoBackend() : new WmiBackend();
            Title = "荣耀硬件助手";
            Width = 620;
            Height = 420;
            ResizeMode = ResizeMode.CanMinimize;
            WindowStartupLocation = WindowStartupLocation.CenterScreen;
            WindowStyle = WindowStyle.None;
            WindowChrome.SetWindowChrome(this, new WindowChrome
            {
                CaptionHeight = caption.Height,
                ResizeBorderThickness = new Thickness(0),
                GlassFrameThickness = new Thickness(0),
                UseAeroCaptionButtons = false
            });
            var layout = new DockPanel();
            DockPanel.SetDock(caption, Dock.Top);
            layout.Children.Add(caption);
            layout.Children.Add(view);
            Content = layout;
            caption.Children.Add(captionTitle);
            var controls = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 4, 0) };
            minimizeButton = CaptionButton("最小化", "M3,8 H13", delegate { SystemCommands.MinimizeWindow(this); });
            closeButton = CaptionButton("关闭", "M4,4 L12,12 M12,4 L4,12", delegate { SystemCommands.CloseWindow(this); });
            controls.Children.Add(minimizeButton);
            controls.Children.Add(closeButton);
            caption.Children.Add(controls);
            ApplyCaptionTheme(false);
            Loaded += Initialize;
            Closing += CloseOrHide;
            Application.Current.SessionEnding += OnSessionEnding;
            refreshTimer.Tick += async delegate { await RefreshInBackground(); };
            Closed += delegate
            {
                closed = true;
                refreshTimer.Stop();
                Application.Current.SessionEnding -= OnSessionEnding;
                if (tray != null)
                {
                    tray.Visible = false;
                    tray.Dispose();
                }
                if (trayMenu != null) trayMenu.Dispose();
                if (trayIcon != null) trayIcon.Dispose();
                view.Dispose();
            };
        }

        void CloseOrHide(object sender, CancelEventArgs e)
        {
            if (exitRequested || !preferences.CloseToTray) return;
            try
            {
                EnsureTray();
                tray.Visible = true;
                Hide();
                e.Cancel = true;
            }
            catch (Exception ex) { AppLog.Write(ex); }
        }

        void EnsureTray()
        {
            if (tray != null) return;
            trayIcon = TrayIconResource.Load();
            trayMenu = new Forms.ContextMenuStrip();
            trayMenu.Items.Add("打开荣耀硬件助手", null, delegate { ShowFromTray(); });
            trayMenu.Items.Add(new Forms.ToolStripSeparator());
            trayMenu.Items.Add("退出", null, delegate { Exit(); });
            tray = new Forms.NotifyIcon { Text = Title, Icon = trayIcon, ContextMenuStrip = trayMenu };
            tray.MouseClick += delegate(object sender, Forms.MouseEventArgs e)
            {
                if (e.Button == Forms.MouseButtons.Left) ShowFromTray();
            };
        }

        internal void ShowFromTray()
        {
            if (closed || exitRequested) return;
            if (!IsVisible) Show();
            if (WindowState == WindowState.Minimized) WindowState = WindowState.Normal;
            Activate();
            if (tray != null) tray.Visible = false;
        }

        void OnSessionEnding(object sender, SessionEndingCancelEventArgs e) { exitRequested = true; }

        void Exit()
        {
            exitRequested = true;
            Close();
        }

        Button CaptionButton(string label, string geometry, Action action)
        {
            var icon = new IconPath { Data = Geometry.Parse(geometry), StrokeThickness = 1.25, StrokeStartLineCap = PenLineCap.Round, StrokeEndLineCap = PenLineCap.Round };
            icon.SetBinding(Shape.StrokeProperty, new System.Windows.Data.Binding("Foreground") { RelativeSource = new System.Windows.Data.RelativeSource(System.Windows.Data.RelativeSourceMode.FindAncestor, typeof(Button), 1) });
            var button = new Button { Width = 42, Height = 32, Content = icon, BorderThickness = new Thickness(0) };
            UpdateCaptionLabel(button, label);
            WindowChrome.SetIsHitTestVisibleInChrome(button, true);
            button.Click += delegate { action(); };
            return button;
        }

        static void UpdateCaptionLabel(Button button, string label)
        {
            button.ToolTip = label;
            AutomationProperties.SetName(button, label);
        }

        void ApplyCaptionTheme(bool dark)
        {
            var background = new SolidColorBrush(dark ? Color.FromRgb(23, 23, 23) : Color.FromRgb(249, 249, 248));
            var foreground = new SolidColorBrush(dark ? Color.FromRgb(236, 236, 236) : Color.FromRgb(32, 32, 31));
            var hover = new SolidColorBrush(dark ? Color.FromRgb(48, 48, 48) : Color.FromRgb(239, 239, 237));
            caption.Background = background;
            captionTitle.Foreground = foreground;
            Background = background;
            view.DefaultBackgroundColor = dark ? System.Drawing.Color.FromArgb(33, 33, 33) : System.Drawing.Color.White;
            foreach (var button in new[] { minimizeButton, closeButton })
            {
                var template = new ControlTemplate(typeof(Button));
                var border = new FrameworkElementFactory(typeof(Border), "Surface");
                border.SetValue(Border.BackgroundProperty, Brushes.Transparent);
                border.SetValue(Border.CornerRadiusProperty, new CornerRadius(6));
                var presenter = new FrameworkElementFactory(typeof(ContentPresenter));
                presenter.SetValue(HorizontalAlignmentProperty, HorizontalAlignment.Center);
                presenter.SetValue(VerticalAlignmentProperty, VerticalAlignment.Center);
                border.AppendChild(presenter);
                template.VisualTree = border;
                var trigger = new Trigger { Property = IsMouseOverProperty, Value = true };
                trigger.Setters.Add(new Setter(Border.BackgroundProperty, hover, "Surface"));
                template.Triggers.Add(trigger);
                button.Template = template;
                button.Foreground = foreground;
            }
        }

        async void Initialize(object sender, RoutedEventArgs e)
        {
            try
            {
                string assets = System.IO.Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "web-dist");
                if (!File.Exists(System.IO.Path.Combine(assets, "index.html"))) throw new FileNotFoundException("未找到界面文件，请重新构建应用。", assets);
                string profile = System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "HonorHardware", "WebView2");
                var env = await CoreWebView2Environment.CreateAsync(null, profile);
                await view.EnsureCoreWebView2Async(env);
                var core = view.CoreWebView2;
                core.Settings.AreDefaultContextMenusEnabled = false;
                core.Settings.AreDevToolsEnabled = false;
                core.Settings.IsStatusBarEnabled = false;
                core.SetVirtualHostNameToFolderMapping("honor.local", assets, CoreWebView2HostResourceAccessKind.DenyCors);
                core.NavigationStarting += delegate(object s, CoreWebView2NavigationStartingEventArgs args) { if (!args.Uri.StartsWith(Origin, StringComparison.OrdinalIgnoreCase)) args.Cancel = true; };
                core.NewWindowRequested += delegate(object s, CoreWebView2NewWindowRequestedEventArgs args) { args.Handled = true; };
                core.PermissionRequested += delegate(object s, CoreWebView2PermissionRequestedEventArgs args) { args.State = CoreWebView2PermissionState.Deny; };
                core.WebMessageReceived += Receive;
                core.Navigate(Origin + "index.html");
            }
            catch (Exception ex)
            {
                AppLog.Write(ex);
                MessageBox.Show("界面无法启动。请确认已安装 Microsoft Edge WebView2 运行时，并检查应用文件是否完整。\n\n" + ex.Message, Title, MessageBoxButton.OK, MessageBoxImage.Error);
                Exit();
            }
        }

        async void Receive(object sender, CoreWebView2WebMessageReceivedEventArgs e)
        {
            if (!string.Equals(e.Source, Origin + "index.html", StringComparison.OrdinalIgnoreCase)) return;
            Dictionary<string, object> message;
            try { message = json.Deserialize<Dictionary<string, object>>(e.WebMessageAsJson); }
            catch { return; }
            if (message == null || !message.ContainsKey("action") || !(message["action"] is string)) return;
            string action = (string)message["action"];
            if (action == "appearance")
            {
                object dark;
                if (message.TryGetValue("dark", out dark) && dark is bool)
                    ApplyCaptionTheme((bool)dark);
                return;
            }
            if (action == "ready")
            {
                Post(new { type = "about", version = Program.Version });
                refreshTimer.Start();
                await Task.WhenAll(ReadAndPostPreferences(), RefreshInBackground());
                return;
            }

            if (action == "autoStart" || action == "closeToTray")
            {
                object value;
                if (!message.TryGetValue("value", out value) || !(value is bool)) return;
                await SavePreference(action, (bool)value);
                return;
            }

            Action operation = GetSettingOperation(action, message);
            if (operation == null) return;

            await hardwareGate.WaitAsync();
            try
            {
                if (closed) return;
                string error = null;
                try { await Task.Run(operation); }
                catch (Exception ex)
                {
                    AppLog.Write(ex);
                    error = "设置失败，请重试。";
                }
                if (!closed) await Refresh();
                Post(new { type = "result", error = error });
            }
            finally { hardwareGate.Release(); }
        }

        async Task SavePreference(string action, bool value)
        {
            string error = null;
            try
            {
                if (action == "autoStart") await Task.Run(delegate { preferences.SetAutoStart(value); });
                else preferences.SetCloseToTray(value);
            }
            catch (Exception ex)
            {
                AppLog.Write(ex);
                error = action == "autoStart" ? "无法更改自动启动，请检查 Windows 任务计划程序。" : "无法保存托盘设置，请重试。";
            }
            await ReadAndPostPreferences();
            Post(new { type = "result", error = error });
        }

        async Task ReadAndPostPreferences()
        {
            bool? autoStart = null;
            string error = null;
            try { autoStart = await Task.Run(new Func<bool>(preferences.ReadAutoStart)); }
            catch (Exception ex)
            {
                AppLog.Write(ex);
                if (error == null) error = "无法读取自动启动状态。";
            }
            Post(new { type = "preferences", autoStart = autoStart, closeToTray = preferences.CloseToTray, error = error });
        }

        Action GetSettingOperation(string action, Dictionary<string, object> message)
        {
            object lowValue, highValue, value;
            if (action == "mode")
            {
                if (!message.TryGetValue("low", out lowValue) || !(lowValue is int) ||
                    !message.TryGetValue("high", out highValue) || !(highValue is int)) return null;
                int low = (int)lowValue;
                int high = (int)highValue;
                if (!((low == 40 && high == 70) || (low == 70 && high == 90) ||
                      (low == 95 && high == 100) || (low == 0 && high == 100))) return null;
                return delegate { backend.SetThreshold(low, high); };
            }

            if (!message.TryGetValue("value", out value) || !(value is bool)) return null;
            bool enabled = (bool)value;
            switch (action)
            {
                case "lid": return delegate { backend.SetLid(enabled); };
                case "pad": return delegate { backend.SetTouchpad(enabled); };
                case "touch": return delegate { backend.SetTouch(enabled); };
                default: return null;
            }
        }

        async Task RefreshInBackground()
        {
            if (closed || !hardwareGate.Wait(0)) return;
            try { await Refresh(); }
            finally { hardwareGate.Release(); }
        }

        async Task Refresh()
        {
            var state = await Task.Run(delegate
            {
                PowerInfo power = null; int[] thresholds = null; bool? lid = null, pad = null; string error = null;
                try { power = backend.ReadPower(); } catch (Exception ex) { AppLog.Write(ex); error = "无法读取电池状态。"; }
                try { thresholds = backend.ReadThreshold(); } catch (Exception ex) { AppLog.Write(ex); error = "请检查驱动和管理员权限，然后重试。"; }
                try { lid = backend.ReadLid(); } catch (Exception ex) { AppLog.Write(ex); }
                try { pad = backend.ReadTouchpad(); } catch (Exception ex) { AppLog.Write(ex); }
                return new { type = "state", demo = demo, percent = power == null || power.Percent < 0 ? (int?)null : power.Percent,
                    online = power == null ? (bool?)null : power.Online, charging = power != null && power.Charging,
                    low = thresholds == null ? (int?)null : thresholds[0], high = thresholds == null ? (int?)null : thresholds[1],
                    lid = lid, pad = pad, available = thresholds != null || lid.HasValue || pad.HasValue,
                    error = error };
            });
            Post(state);
        }
        void Post(object value) { if (!closed && view.CoreWebView2 != null) view.CoreWebView2.PostWebMessageAsJson(json.Serialize(value)); }
    }
}
