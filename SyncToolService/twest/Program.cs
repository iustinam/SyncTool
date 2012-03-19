using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using Microsoft.Win32;

namespace twest
{
    class Program
    {
        static void Main(string[] args)
        {
            RegistryKey myKey = Registry.LocalMachine.OpenSubKey(
                "SYSTEM\\CurrentControlSet\\Services\\SyncToolService", true);

            myKey.SetValue("ImagePath", myKey.GetValue("ImagePath") + " -conf D:\\_eclipse\\conf.xml", RegistryValueKind.String);

        }
    }
}
