using System;
using System.IO;
using System.Linq;
using System.Management;
using System.Security.Principal;
using System.Threading;
using Forms = System.Windows.Forms;

namespace HonorHardware
{
    internal sealed class PowerInfo
    {
        public int Percent;
        public bool? Online;
        public bool Charging;
        public string State;
    }

    internal interface IBackend
    {
        PowerInfo ReadPower();
        int[] ReadThreshold();
        bool? ReadLid();
        bool? ReadTouchpad();
        void SetThreshold(int low, int high);
        void SetLid(bool on);
        void SetTouch(bool on);
        void SetTouchpad(bool on);
    }

    internal static class Hardware
    {
        public static bool IsAdministrator()
        {
            try
            {
                using (var identity = WindowsIdentity.GetCurrent())
                    return new WindowsPrincipal(identity).IsInRole(WindowsBuiltInRole.Administrator);
            }
            catch
            {
                return false;
            }
        }
    }

    internal static class AppLog
    {
        public static void Write(Exception error)
        {
            try
            {
                string directory = Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                    "HonorHardware");
                Directory.CreateDirectory(directory);
                string line = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + "  " + error + Environment.NewLine;
                File.AppendAllText(Path.Combine(directory, "app.log"), line);
            }
            catch
            {
            }
        }
    }

    internal sealed class WmiBackend : IBackend
    {
        public PowerInfo ReadPower()
        {
            var status = Forms.SystemInformation.PowerStatus;
            var info = new PowerInfo
            {
                Percent = status.BatteryLifePercent < 0 ? -1 : (int)Math.Round(status.BatteryLifePercent * 100),
                State = "未知"
            };
            if (status.PowerLineStatus == Forms.PowerLineStatus.Online) info.Online = true;
            else if (status.PowerLineStatus == Forms.PowerLineStatus.Offline) info.Online = false;

            try
            {
                using (var searcher = new ManagementObjectSearcher(@"root\wmi", "SELECT Charging, Discharging FROM BatteryStatus"))
                using (var rows = searcher.Get())
                {
                    var batteries = rows.Cast<ManagementObject>().ToArray();
                    if (batteries.Length > 0)
                    {
                        bool charging = batteries.Any(b => b["Charging"] is bool && (bool)b["Charging"]);
                        bool discharging = batteries.Any(b => b["Discharging"] is bool && (bool)b["Discharging"]);
                        if (charging)
                        {
                            info.Charging = true;
                            info.State = "充电中";
                        }
                        else if (discharging)
                        {
                            info.State = "放电中";
                        }
                        else if (batteries.All(b => b["Charging"] is bool && b["Discharging"] is bool))
                        {
                            info.State = "未充电";
                        }
                    }
                }
            }
            catch
            {
            }
            return info;
        }

        public int[] ReadThreshold()
        {
            var result = Call(0x03, 0x11);
            return new[] { (int)result[1], (int)result[2] };
        }

        public bool? ReadLid()
        {
            var result = Call(0x06, 0x1E);
            return ToBool(result[1]);
        }

        public bool? ReadTouchpad()
        {
            var result = Call(0x02, 0x0F);
            return ToBool(result[1]);
        }

        static bool? ToBool(byte value)
        {
            if (value == 1) return true;
            if (value == 0) return false;
            return null;
        }

        public void SetThreshold(int low, int high)
        {
            Call(0x03, 0x10, (byte)low, (byte)high);
        }

        public void SetLid(bool on)
        {
            Call(0x06, 0x1D, on ? (byte)1 : (byte)0);
        }

        public void SetTouch(bool on)
        {
            Call(0x02, 0x15, on ? (byte)1 : (byte)0);
        }

        public void SetTouchpad(bool on)
        {
            Call(0x02, 0x10, on ? (byte)1 : (byte)0);
        }

        static byte[] Call(params byte[] command)
        {
            using (var search = new ManagementObjectSearcher(@"root\wmi", "SELECT * FROM OemWMIMethod"))
            using (var list = search.Get())
            {
                var device = list.Cast<ManagementObject>().FirstOrDefault();
                if (device == null) throw new InvalidOperationException("未找到 OemWMIMethod，请检查荣耀 WMI 驱动是否安装。");
                using (device)
                using (var input = device.GetMethodParameters("OemWMIfun"))
                {
                    var data = new byte[64];
                    Array.Copy(command, data, command.Length);
                    input["u8Input"] = data;
                    using (var output = device.InvokeMethod("OemWMIfun", input, null))
                    {
                        if (output == null) throw new InvalidOperationException("硬件未返回数据。");
                        var result = output["u8Output"] as byte[];
                        if (result == null || result.Length < 3) throw new InvalidOperationException("硬件返回数据不完整。");
                        if (result[0] != 0) throw new InvalidOperationException("硬件返回错误代码：" + result[0]);
                        return result;
                    }
                }
            }
        }
    }

    internal sealed class DemoBackend : IBackend
    {
        int low = 70;
        int high = 90;
        bool lid = true;
        bool pad = true;

        public PowerInfo ReadPower()
        {
            Thread.Sleep(140);
            return new PowerInfo { Percent = 68, Online = true, Charging = true, State = "充电中" };
        }

        public int[] ReadThreshold()
        {
            Thread.Sleep(120);
            return new[] { low, high };
        }

        public bool? ReadLid()
        {
            Thread.Sleep(60);
            return lid;
        }

        public bool? ReadTouchpad()
        {
            Thread.Sleep(60);
            return pad;
        }

        public void SetThreshold(int newLow, int newHigh)
        {
            Thread.Sleep(220);
            low = newLow;
            high = newHigh;
        }

        public void SetLid(bool on)
        {
            Thread.Sleep(200);
            lid = on;
        }

        public void SetTouch(bool on)
        {
            Thread.Sleep(200);
        }

        public void SetTouchpad(bool on)
        {
            Thread.Sleep(200);
            pad = on;
        }
    }
}
