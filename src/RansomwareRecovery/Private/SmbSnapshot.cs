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
        private const int StatusBufferOverflow = unchecked((int)0x80000005);

        // SRV_SNAPSHOT_ARRAY: three ULONGs followed by a multi-string of @GMT tokens.
        private const int HeaderSize = 12;

        [StructLayout(LayoutKind.Sequential)]
        private struct IoStatusBlock
        {
            public IntPtr Status;
            public UIntPtr Information;
        }

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern SafeFileHandle CreateFileW(
            string fileName, uint desiredAccess, uint shareMode, IntPtr securityAttributes,
            uint creationDisposition, uint flagsAndAttributes, IntPtr templateFile);

        // DeviceIoControl only issues IRP_MJ_FILE_SYSTEM_CONTROL for FILE_DEVICE_FILE_SYSTEM
        // codes; this FSCTL uses FILE_DEVICE_NETWORK_FILE_SYSTEM, so call ntdll directly.
        [DllImport("ntdll.dll")]
        private static extern int NtFsControlFile(
            SafeFileHandle fileHandle, IntPtr eventHandle, IntPtr apcRoutine, IntPtr apcContext,
            out IoStatusBlock ioStatusBlock, uint fsControlCode, IntPtr inputBuffer, uint inputBufferLength,
            byte[] outputBuffer, uint outputBufferLength);

        [DllImport("ntdll.dll")]
        private static extern int RtlNtStatusToDosError(int status);

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
            IoStatusBlock ioStatus;
            int status = NtFsControlFile(handle, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, out ioStatus,
                FsctlSrvEnumerateSnapshots, IntPtr.Zero, 0, buffer, size);
            if (status < 0 && status != StatusBufferOverflow)
            {
                int error = RtlNtStatusToDosError(status);
                throw new Win32Exception(error, string.Format(
                    "FSCTL_SRV_ENUMERATE_SNAPSHOTS failed with NTSTATUS 0x{0:X8}: {1}",
                    status, new Win32Exception(error).Message));
            }
            return buffer;
        }
    }
}
