using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.Principal;
using Microsoft.Win32;

namespace HonorHardware
{
    internal sealed class AppPreferences
    {
        const string RegistryPath = @"Software\HonorHardware";
        const string TrayValue = "CloseToTray";
        const int InteractiveToken = 3;
        const int HighestRunLevel = 1;
        const int LogonTrigger = 9;
        const int ExecuteAction = 0;
        const int CreateOrUpdate = 6;
        const int FileNotFound = unchecked((int)0x80070002);

        readonly bool demo;
        readonly string executable;
        readonly string sid;
        bool demoStartup;

        public AppPreferences(bool demo, string executable, string sid)
        {
            this.demo = demo;
            this.executable = executable;
            this.sid = sid;
            if (demo) return;

            try
            {
                using (var key = Registry.CurrentUser.OpenSubKey(RegistryPath))
                    CloseToTray = key != null && Equals(key.GetValue(TrayValue), 1);
            }
            catch (Exception ex) { AppLog.Write(ex); }
        }

        public bool CloseToTray { get; private set; }

        public void SetCloseToTray(bool enabled)
        {
            if (!demo)
            {
                using (var key = Registry.CurrentUser.CreateSubKey(RegistryPath))
                    key.SetValue(TrayValue, enabled ? 1 : 0, RegistryValueKind.DWord);
            }
            CloseToTray = enabled;
        }

        string TaskName { get { return "HonorHardwareManager-Logon-" + sid; } }

        public bool ReadAutoStart()
        {
            if (demo) return demoStartup;

            dynamic service = ConnectScheduler();
            dynamic folder = service.GetFolder(@"\");
            try
            {
                dynamic task = folder.GetTask(TaskName);
                if (!(bool)task.Enabled || (int)task.Definition.Actions.Count != 1) return false;
                string path = task.Definition.Actions.Item(1).Path;
                return string.Equals(path, executable, StringComparison.OrdinalIgnoreCase);
            }
            catch (FileNotFoundException) { return false; }
            catch (COMException ex)
            {
                if (ex.ErrorCode == FileNotFound) return false;
                throw;
            }
        }

        public void SetAutoStart(bool enabled)
        {
            if (demo)
            {
                demoStartup = enabled;
                return;
            }

            dynamic service = ConnectScheduler();
            dynamic folder = service.GetFolder(@"\");
            if (!enabled)
            {
                try { folder.DeleteTask(TaskName, 0); }
                catch (FileNotFoundException) { }
                catch (COMException ex) { if (ex.ErrorCode != FileNotFound) throw; }
                return;
            }

            dynamic task = service.NewTask(0);
            task.RegistrationInfo.Description = "登录 Windows 后启动荣耀硬件助手。";
            task.Principal.UserId = sid;
            task.Principal.LogonType = InteractiveToken;
            task.Principal.RunLevel = HighestRunLevel;
            task.Settings.DisallowStartIfOnBatteries = false;
            task.Settings.StopIfGoingOnBatteries = false;
            task.Settings.ExecutionTimeLimit = "PT0S";
            task.Settings.AllowDemandStart = false;

            dynamic trigger = task.Triggers.Create(LogonTrigger);
            trigger.UserId = sid;
            dynamic action = task.Actions.Create(ExecuteAction);
            action.Path = executable;
            action.Arguments = "--startup";
            action.WorkingDirectory = Path.GetDirectoryName(executable);
            folder.RegisterTaskDefinition(TaskName, task, CreateOrUpdate, sid, null, InteractiveToken, null);
        }

        static object ConnectScheduler()
        {
            dynamic service = Activator.CreateInstance(Type.GetTypeFromProgID("Schedule.Service", true));
            service.Connect();
            return service;
        }
    }
}
