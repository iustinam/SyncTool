using System;
using System.Collections.Generic;
using System.Linq;
using System.Web;
using System.Xml;
using System.IO;

namespace SyncToolGUI.Models
{
    public class AppConfiguration
    {
        public String ConfPath { get; set; }
        public String SyncScriptPath { get; set; }
        public String JobsConfPath { get; set; }
        public String PortFilesPath { get; set; }
        public int TouchPortFileTime { get; set; } 
        private SyncToolDBContainer _dbcontainer = new SyncToolDBContainer();
        

        //singleton
        private static AppConfiguration _instance;
        public static AppConfiguration Instance
        {
            get
            {
                if (_instance == null)
                    _instance = new AppConfiguration();
                return _instance;
            }
        }

        private AppConfiguration()
        {
            var conf = (from s in _dbcontainer.Configurations
                        where s.Name == "conf_path"
                        select s.Value).ToList();
            if (conf.Count == 1)
                ConfPath = conf[0];
            this._loadPaths();
        }

        private void _loadPaths()
        {
            XmlDocument doc = new XmlDocument();
            if (File.Exists(ConfPath))
            {
                doc.Load(ConfPath);
                XmlElement elem = doc.DocumentElement;
                string runfolder = ((XmlElement)elem.GetElementsByTagName("running_folder").Item(0)).InnerText;
                if ((runfolder[runfolder.Length - 1] != '\\') || (runfolder[runfolder.Length - 1] != '/'))
                    runfolder = runfolder + "\\";

                SyncScriptPath = runfolder + ((XmlElement)elem.GetElementsByTagName("sync_path").Item(0)).InnerText;
                JobsConfPath = runfolder + ((XmlElement)elem.GetElementsByTagName("jobs_conf_filename").Item(0)).InnerText;
                PortFilesPath = runfolder + ((XmlElement)elem.GetElementsByTagName("portfiles").Item(0)).InnerText;
                TouchPortFileTime = Int32.Parse(((XmlElement)elem.GetElementsByTagName("touch_portfile_time").Item(0)).InnerText);
            }
        }
    }
}