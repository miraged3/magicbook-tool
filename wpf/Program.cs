using System;
using System.Diagnostics;
using System.Reflection;
using System.Security.Principal;
using System.Threading;
using System.Windows;

[assembly: AssemblyVersion(HonorHardware.Program.Version + ".0")]
[assembly: AssemblyFileVersion(HonorHardware.Program.Version + ".0")]
[assembly: AssemblyInformationalVersion(HonorHardware.Program.Version)]

namespace HonorHardware
{
    internal static class Program
    {
        internal const string Version = "1.0.0";

        [STAThread]
        private static void Main(string[] args)
        {
            bool demo = false;
            bool startup = false;
            for (int i = 0; i < args.Length; i++)
            {
                if (string.Equals(args[i], "--demo", StringComparison.OrdinalIgnoreCase)) demo = true;
                if (string.Equals(args[i], "--startup", StringComparison.OrdinalIgnoreCase)) startup = true;
            }

            string sid;
            using (var identity = WindowsIdentity.GetCurrent())
                sid = identity.User.Value;

            var settings = new AppPreferences(demo, Process.GetCurrentProcess().MainModule.FileName, sid);
            var app = new Application { ShutdownMode = ShutdownMode.OnMainWindowClose };
            if (demo)
            {
                app.Run(new WebWindow(true, settings));
                return;
            }

            bool firstInstance;
            using (var showExisting = new EventWaitHandle(false, EventResetMode.AutoReset,
                @"Local\HonorHardwareManager.Show." + sid, out firstInstance))
            {
                if (!firstInstance)
                {
                    if (!startup) showExisting.Set();
                    return;
                }

                var window = new WebWindow(false, settings);
                var listener = ThreadPool.RegisterWaitForSingleObject(showExisting, delegate
                {
                    window.Dispatcher.BeginInvoke(new Action(window.ShowFromTray));
                }, null, Timeout.Infinite, false);
                try { app.Run(window); }
                finally { listener.Unregister(null); }
            }
        }
    }
}
