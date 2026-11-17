using System;
using System.Drawing;
using System.Runtime.InteropServices;

namespace HonorHardware
{
    internal static class TrayIconResource
    {
        const int GroupIcon = 14;
        const int SmallIcon = 0;

        delegate bool ResourceNameCallback(IntPtr module, IntPtr type, IntPtr name, IntPtr parameter);

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
        static extern IntPtr GetModuleHandle(string moduleName);

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
        static extern bool EnumResourceNames(IntPtr module, IntPtr type, ResourceNameCallback callback, IntPtr parameter);

        [DllImport("comctl32.dll", ExactSpelling = true)]
        static extern int LoadIconMetric(IntPtr module, IntPtr name, int metric, out IntPtr icon);

        [DllImport("user32.dll")]
        static extern bool DestroyIcon(IntPtr icon);

        public static Icon Load()
        {
            Icon result = null;
            IntPtr module = GetModuleHandle(null);
            EnumResourceNames(module, new IntPtr(GroupIcon), delegate(IntPtr resourceModule, IntPtr type, IntPtr name, IntPtr parameter)
            {
                IntPtr icon;
                if (LoadIconMetric(resourceModule, name, SmallIcon, out icon) < 0 || icon == IntPtr.Zero)
                    return true;
                try
                {
                    using (var borrowedIcon = Icon.FromHandle(icon))
                        result = (Icon)borrowedIcon.Clone();
                }
                finally { DestroyIcon(icon); }
                return false;
            }, IntPtr.Zero);
            return result ?? Icon.ExtractAssociatedIcon(typeof(TrayIconResource).Assembly.Location);
        }
    }
}
