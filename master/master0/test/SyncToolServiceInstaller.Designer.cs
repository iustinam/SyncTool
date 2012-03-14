namespace master0
{
    partial class SyncToolServiceInstaller
    {
        /// <summary>
        /// Required designer variable.
        /// </summary>
        private System.ComponentModel.IContainer components = null;

        /// <summary> 
        /// Clean up any resources being used.
        /// </summary>
        /// <param name="disposing">true if managed resources should be disposed; otherwise, false.</param>
        protected override void Dispose(bool disposing)
        {
            if (disposing && (components != null))
            {
                components.Dispose();
            }
            base.Dispose(disposing);
        }

        #region Component Designer generated code

        /// <summary>
        /// Required method for Designer support - do not modify
        /// the contents of this method with the code editor.
        /// </summary>
        private void InitializeComponent()
        {
            this.SyncToolProcessInstaller = new System.ServiceProcess.ServiceProcessInstaller();
            this.SyncToolInstaller = new System.ServiceProcess.ServiceInstaller();
            // 
            // SyncToolProcessInstaller
            // 
            this.SyncToolProcessInstaller.Password = null;
            this.SyncToolProcessInstaller.Username = null;
            this.SyncToolProcessInstaller.AfterInstall += new System.Configuration.Install.InstallEventHandler(this.serviceProcessInstaller1_AfterInstall);
            // 
            // SyncToolInstaller
            // 
            this.SyncToolInstaller.Description = "installer";
            this.SyncToolInstaller.DisplayName = "SyncTool";
            this.SyncToolInstaller.ServiceName = "SyncToolService";
            this.SyncToolInstaller.AfterInstall += new System.Configuration.Install.InstallEventHandler(this.serviceInstaller1_AfterInstall);
            // 
            // SyncMasterServiceInstaller
            // 
            this.Installers.AddRange(new System.Configuration.Install.Installer[] {
            this.SyncToolInstaller});

        }

        #endregion

        private System.ServiceProcess.ServiceProcessInstaller SyncToolProcessInstaller;
        private System.ServiceProcess.ServiceInstaller SyncToolInstaller;
    }
}