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
        ServiceProcessInstaller processInstaller;

        public SyncToolInstaller()
        {
            processInstaller = new ServiceProcessInstaller();
            var serviceInstaller = new ServiceInstaller();

            //set the privileges
            processInstaller.Account = ServiceAccount.User;

            serviceInstaller.DisplayName = "SyncTool";
            serviceInstaller.StartType = ServiceStartMode.Automatic;
            //serviceInstaller.Context.Parameters.Add("conf","D:\\_eclipse\\conf.xml");
            
            //must be the same as what was set in Program's constructor
            serviceInstaller.ServiceName = "SyncToolService";

            this.Installers.Add(processInstaller);
            this.Installers.Add(serviceInstaller);

            this.BeforeInstall += new InstallEventHandler(SyncToolInstaller_BeforeInstall);
        }

        void SyncToolInstaller_BeforeInstall(object sender, InstallEventArgs e)
        {
            if (!String.IsNullOrEmpty(this.Context.Parameters["user"]))
            {
                this.processInstaller.Username = this.Context.Parameters["user"];
            }
            if (!String.IsNullOrEmpty(this.Context.Parameters["pass"]))
            {
                this.processInstaller.Password = this.Context.Parameters["pass"];
            }
        }
    }
}
