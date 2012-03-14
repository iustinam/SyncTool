using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Configuration.Install;
using System.ComponentModel;
using System.ServiceProcess;

namespace master0
{
    [RunInstaller(true)]
    public class SyncToolInstaller : Installer
    {
        public SyncToolInstaller()
        {
            var processInstaller = new ServiceProcessInstaller();
            var serviceInstaller = new ServiceInstaller();

            //set the privileges
            processInstaller.Account = ServiceAccount.LocalSystem;

            serviceInstaller.DisplayName = "SyncTool";
            serviceInstaller.StartType = ServiceStartMode.Manual;

            //must be the same as what was set in Program's constructor
            serviceInstaller.ServiceName = "SyncToolService";

            this.Installers.Add(processInstaller);
            this.Installers.Add(serviceInstaller);
        }
    }
}
