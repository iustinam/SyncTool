using System;
using System.Collections.Generic;
using System.Linq;
using System.Web;
using System.Threading;
using System.IO;
using System.Text.RegularExpressions;
using System.Net.Sockets;

namespace SyncToolGUI.Models {
    public class ProcessManager {
        //este creat de controller la int fix
        //cauta procese noi (portfiles)ce apartin unui anumit job
        //creaza threaduri pentru fiecare in care face socket (cere statistici si primeste) 
        //cui trimite statistica.. trimite la controller care il face ob json si il trim la view
        //controller prim get pt un url si ii cere astuia obiectul JobStatistics (cu lista ..)
        //lista de thr? nu ar trebui si un JobManager? care porneste astea in thr sep si le face join

        //intros la controller (will create json)
        private SyncJobStatistics _jobStatistics =new SyncJobStatistics();
        //contine path-ul catre folderul cu portfiles
        private AppConfiguration _appConf=AppConfiguration.Instance;
        //id proces, statistica
        private Dictionary<int, string> _stats = new Dictionary<int, string>();

       // Mutex locker = new Mutex();
        private Dictionary<int,ManualResetEvent> doneEvents=new Dictionary<int,ManualResetEvent>();
        private List<Thread> _threads = new List<Thread>();

        public SyncJobStatistics GetStatisticsForJob(int jobId)
        {
            //cautam fisiere portfile existente cu id-ul jobului dat
            Regex re = new Regex(jobId+"\\.([0-9]+)\\.([0-9]+)\\.portfile");
            string[] filePaths = Directory.GetFiles(this._appConf.PortFilesPath,"*portfile");

            //cream threaduri pentru fiecare proces, in care cerem statisticile
            foreach (string s in filePaths)
            {
                Match m=re.Match(s);
                if (m.Success)
                {
                    int port = Int32.Parse(m.Groups[2].ToString());
                    FileInfo finf = new FileInfo(s);
                    //if (DateTime.Now.Subtract(finf.LastWriteTime).TotalSeconds > _appConf.TouchPortFileTime+1)
                    //{
                    //    //ignore
                    //}
                    //else
                    //{
                        ManualResetEvent ev = new ManualResetEvent(false);
                        this.doneEvents[port] = ev;

                        ThreadPool.QueueUserWorkItem(HandleProcess,port);
                        
                        //t.Start(port);
                        //this._threads.Add(t);
                    //}
                }
            }
            bool allFinished;
            if(doneEvents.Count>0)
                 allFinished =WaitHandle.WaitAll(doneEvents.Values.ToArray(), 500);

            return this._jobStatistics;
        }

        
        public void HandleProcess(Object port)
        {
            int p =(int)port;
            //trimite cerere de statistici si primeste raspuns pe un socket
            //lock, seteaza resetEvent-ul portului respectiv cand termina
            //lock , adauga statisticile in JobStatistics

            ProcessStatistics ps=null;
            try
            {
                Socket sock = new Socket(AddressFamily.InterNetwork, SocketType.Stream, ProtocolType.Tcp);
                System.Net.IPAddress ip = System.Net.IPAddress.Parse("127.0.0.1");
                System.Net.IPEndPoint remEP = new System.Net.IPEndPoint(ip,(Int32) port);
                sock.Connect(remEP);
                byte[] data = System.Text.Encoding.ASCII.GetBytes("2");
                sock.Send(data);
                byte[] recvData=new byte[4000];
                int received = 0;
                string response;

                while((received = sock.Receive(recvData)) <= 0) ;

                if (received > 0)
                {
                    response = System.Text.Encoding.UTF8.GetString(recvData);
                    string[] param1=response.Split('_');
                    int[] param = new int[param1.Count()];
                    for(int i=0;i<param1.Count();i++)
                    {
                        param[i] = Int32.Parse(param1[i]);
                    }
                    ps= new ProcessStatistics(param[1],param[2],param[3],param[4],param[5]
                        ,param[6],param[7],param[8],param[9],DateTime.Now,DateTime.Now);

                }   
            }
            catch (Exception ex)
            {
                
                //;
            }
            lock (this)
            {
                if(ps!=null)
                    this._jobStatistics.ProcessStatisticsList.Add(ps);
                this.doneEvents[p].Set();
            }
        }
    }
}