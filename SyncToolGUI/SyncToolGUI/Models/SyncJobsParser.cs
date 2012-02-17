using System;
using System.Collections.Generic;
using System.Linq;
using System.Web;
using System.Xml;
using System.IO;

namespace SyncToolGUI.Models
{
    public class SyncJobsParser
    {
        private Dictionary<int, SyncJob> _syncJobs=new Dictionary<int,SyncJob>();
        private static SyncJobsParser _instance=new SyncJobsParser();
        private SyncJobsParser()
        {
        }
        public static SyncJobsParser Instance
        {
            get { return _instance; }
        }
        private Boolean _initialized=false;

        public void LoadJobs(string jobsConfPath)
        {
            XmlDocument doc = new XmlDocument();
            if (File.Exists(jobsConfPath))
            {
                doc.Load(jobsConfPath);
                XmlElement elem = doc.DocumentElement;

                String name, master, start;
                int id;

                //for every job
                foreach (XmlElement item in elem.ChildNodes)
                {
                    Dictionary<String, String> clients = new Dictionary<String, String>();
                    HashSet<String> excl = new HashSet<string>();
                    HashSet<String> exclre = new HashSet<string>();

                    XmlElement nameNode = (XmlElement)item.GetElementsByTagName("title").Item(0);
                    XmlElement masterNode = (XmlElement)item.GetElementsByTagName("master").Item(0);
                    XmlElement idNode = (XmlElement)item.GetElementsByTagName("id").Item(0);
                    XmlElement ignore = (XmlElement)item.GetElementsByTagName("ignore").Item(0);

                    XmlElement startNode = (XmlElement)item.GetElementsByTagName("start").Item(0);
                    XmlNodeList clientNodes = item.GetElementsByTagName("client");
                    XmlNodeList exclNodes = item.GetElementsByTagName("exclude");
                    XmlNodeList exclreNodes = item.GetElementsByTagName("exclude_re");
                    if (nameNode == null || idNode == null || masterNode == null || clientNodes.Count == 0 || startNode == null)
                    {
                        //  invalid , next
                    }
                    else
                    {
                        name = nameNode.InnerText;
                        id = Int32.Parse(idNode.InnerText);
                        start = startNode.InnerText;
                        master = masterNode.InnerText;

                        HashSet<String> noDuplCli = new HashSet<string>(); //be sure there are no duplicates clients
                        foreach (XmlElement cli in clientNodes)
                        {
                            String addr = ((XmlElement)cli.GetElementsByTagName("addr").Item(0)).InnerText;
                            if (!noDuplCli.Contains(addr))
                            {
                                clients.Add(((XmlElement)cli.GetElementsByTagName("id").Item(0)).InnerText, addr);
                            }
                            noDuplCli.Add(addr);
                        }
                        foreach (XmlElement ex in exclNodes)
                        {
                            excl.Add(ex.InnerText);
                        }
                        foreach (XmlElement ex in exclreNodes)
                        {
                            exclre.Add(ex.InnerText);
                        }
                       
                        SyncJob sj = new SyncJob(name, id, start, master, clients, excl, exclre);

                        //calculate delay period for first run
                        //if "start" time has passed today calculate the time for the following day, else calculate time for today.
                        //DateTime dt = Convert.ToDateTime(start);
                        //if (DateTime.Now.CompareTo(dt) > 0)
                        //{
                        //    dt = dt.AddDays(1);
                        //}
                        //TimeSpan span1 = TimeSpan.FromSeconds((double)(dt.Ticks - DateTime.Now.Ticks) / 10000000);

                        this._syncJobs.Add(id, sj);
                    }
                }//ended iterating through job elements
            }
            else
            {
               // _log.WriteLine("ERR: opening jobs_conf :{0}", _jobsConfPath);
            }

            this._initialized = true;
        }

        public List<SyncJob> GetAllSyncJobs()
        {
            if (!this._initialized) this.LoadJobs(@"C:\synctool\jobs_conf.xml");
            return this._syncJobs.Values.ToList<SyncJob>(); 
        }

        public SyncJob GetJob(int id)
        {
            return this._syncJobs[id];
        }

    }
}