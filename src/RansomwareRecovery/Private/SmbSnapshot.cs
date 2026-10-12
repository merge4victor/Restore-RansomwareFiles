using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32.SafeHandles;

namespace RansomwareRecovery
{
    public static class SmbSnapshot
    {
        private const uint FsctlSrvEnumerateSnapshots = 0x00144064;
        private const uint GenericRead = 0x80000000;
        private const uint FileShareAll = 0x00000007;
        private const uint OpenExisting = 3;
        private const uint FileFlagBackupSemantics = 0x02000000;
        private const int ErrorMoreData = 234;

        // SRV_SNAPSHOT_ARRAY: three ULONGs followed by a multi-string of @GMT tokens.
        private const int HeaderSize = 12;

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern SafeFileHandle CreateFileW(
            string fileName, uint desiredAccess, uint shareMode, IntPtr securityAttributes,
            uint creationDisposition, uint flagsAndAttributes, IntPtr templateFile);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool DeviceIoControl(
            SafeFileHandle device, uint ioControlCode, IntPtr inBuffer, uint inBufferSize,
            byte[] outBuffer, uint outBufferSize, out uint bytesReturned, IntPtr overlapped);

        public static string[] GetTokens(string shareRoot)
        {
            string path = shareRoot.TrimEnd('\\') + "\\";
            using (SafeFileHandle handle = CreateFileW(path, GenericRead, FileShareAll, IntPtr.Zero,
                OpenExisting, FileFlagBackupSemantics, IntPtr.Zero))
            {
                if (handle.IsInvalid)
                {
                    throw new Win32Exception(Marshal.GetLastWin32Error(), "Cannot open share " + path);
                }

                byte[] header = Query(handle, HeaderSize + 4);
                int arraySize = BitConverter.ToInt32(header, 8);
                if (arraySize <= 0)
                {
                    return new string[0];
                }

                byte[] full = Query(handle, (uint)(HeaderSize + arraySize));
                string multiString = Encoding.Unicode.GetString(full, HeaderSize, arraySize);
                return multiString.Split(new[] { '\0' }, StringSplitOptions.RemoveEmptyEntries);
            }
        }

        private static byte[] Query(SafeFileHandle handle, uint size)
        {
            byte[] buffer = new byte[size];
            uint bytesReturned;
            if (!DeviceIoControl(handle, FsctlSrvEnumerateSnapshots, IntPtr.Zero, 0, buffer, size,
                out bytesReturned, IntPtr.Zero))
            {
                int error = Marshal.GetLastWin32Error();
                if (error != ErrorMoreData)
                {
                    throw new Win32Exception(error, "FSCTL_SRV_ENUMERATE_SNAPSHOTS failed");
                }
            }
            return buffer;
        }
    }
}
