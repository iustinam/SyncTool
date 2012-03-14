using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Text;
using System.ServiceProcess;
using System.IO;
using System.Threading;
using System.Xml;
using System.Text.RegularExpressions;
using System.Net;
using System.Net.Sockets;

namespace master0
{
    public partial class SyncToolService : ServiceBase
    {
        private String CONF_PATH = @"D:\synctool\conf.xml";               //contains the paths below
        private const String LOG_PATH = @"D:\synctool\sync_service.log";
        private const String LOG_DIR = @"D:\synctol\";
        private const String RUN_LOG_DIR = "Logs";

        private String _servRunningFile;
        TextWriter _log;
        private String _jobsConfPath;          //jobs conf file
        private String _syncScriptPath;        //sync.pl path
        private String _runFolder;  //folder that keeps running files and portfiles
        private HashSet<Process> _procs; //processes to kill when stopping
        private int _touchPortfileTime=3;

        private LinkedList<System.Threading.Timer> _timers;
        private Thread _workerThread;
        //private Thread _stopperThread;
        private Thread _listener;
        private int _run;
        private string[] _args;
        private Boolean _debug;     //use when you want to create the .debug file for each sync 
        private Boolean _initialized;

        //====================================================================================================
        static void Main(string[] args)
        {
            ServiceBase.Run(new SyncToolService());
        }
        //====================================================================================================
        public SyncToolService()
        {            
            InitializeComponent();

            //_timer = new System.Timers.Timer(6000);
            //_timer.AutoReset = false;
            //_timer.Elapsed+=new System.Timers.ElapsedEventHandler(TimerElapsed);
        }

        //====================================================================================================
        private void InitializeComponent()
        {
            this.CanHandlePowerEvent = true;
            this.CanHandleSessionChangeEvent = true;
            this.CanPauseAndContinue = true;
            this.CanShutdown = true;
            this.ServiceName = "SyncToolService";

        }
        //====================================================================================================
        protected override void OnStart(string[] args)
        {
            base.OnStart(args);
            _args = args;
            //_timer.Start();
            //_log = new StreamWriter(LOG_PATH, true);
            //((StreamWriter)_log).AutoFlush = true;
            //_log.WriteLine("opened");
            //_log.Close();

            _timers = new LinkedList<Timer>();
            _procs = new HashSet<Process>();
            _run = 1;
            _debug = false;
            _initialized = false;
                       
            _workerThread = new Thread(new ThreadStart(Worker));
            _workerThread.Start();

            _listener = new Thread(new ThreadStart(ListenConfChange));
            _listener.Start();


            ////if ((_workerThread == null) ||
            ////   ((_workerThread.ThreadState &
            ////    (System.Threading.ThreadState.Unstarted | System.Threading.ThreadState.Stopped)) != 0))
            ////{
            //    _workerThread=new Thread(new ThreadStart(Worker));
            //    _workerThread.Start();
            //    TextWriter tw = new StreamWriter("D:\\date.txt", true);
            //    tw.WriteLine("on start : " + DateTime.Now.ToShortDateString() + " " + DateTime.Now.ToShortTimeString());
            //    tw.Close();
            ////}
        }
        //====================================================================================================
        private void init()
        {
            //open log
            if (!File.Exists(LOG_PATH))
            {
                if (!Directory.Exists(LOG_DIR))
                    Directory.CreateDirectory(LOG_DIR);
                File.Create (LOG_PATH);
            }
            _log = new StreamWriter(LOG_PATH, true);
            ((StreamWriter)_log).AutoFlush = true;
            _log.WriteLine("==================================================================================================================");
            _log.WriteLine("opened " + DateTime.Now.ToShortDateString() + " " + DateTime.Now.ToShortTimeString());

            if (_args.Count() > 0)
            {
                _log.WriteLine("args:");
                for (int i = 0; i < _args.Count(); i++)
                {
                    _log.WriteLine(_args[i]);
                    if (_args[i].Equals("-debug"))
                    {
                        _debug = true;
                    }
                    if (_args[i].Equals("-conf"))
                    {
                        if (!(_args.Count() > i))
                        {
                            _log.WriteLine("ERROR: invalid args, give the conf path after -conf");
                        }
                        CONF_PATH = _args[i + 1];
                        _log.WriteLine("conf path is "+CONF_PATH);
                        i++;
                    }
                }
            }

            //get paths 
            XmlDocument doc = new XmlDocument();
            if (File.Exists(CONF_PATH))
            {
                _log.WriteLine("{0} exists", CONF_PATH);
                doc.Load(CONF_PATH);
                XmlElement elem = doc.DocumentElement; //<conf>

                lock (this)
                {
                    
                    _runFolder = ((XmlElement)elem.GetElementsByTagName("running_folder").Item(0)).InnerText;
                    if (!_runFolder.EndsWith("/"))
                    {
                        _runFolder += "/";
                    }
                    _log.WriteLine("running folder: " + _runFolder);
                    _jobsConfPath = _runFolder+((XmlElement)elem.GetElementsByTagName("jobs_conf_filename").Item(0)).InnerText;
                    _log.WriteLine("_jobsConfPath " + _jobsConfPath);
                    _syncScriptPath = _runFolder + ((XmlElement)elem.GetElementsByTagName("sync_path").Item(0)).InnerText;
                    _log.WriteLine("_syncScriptPath "+_syncScriptPath);
                    _touchPortfileTime = Int32.Parse(((XmlElement)elem.GetElementsByTagName("touch_portfile_time").Item(0)).InnerText);
                    
                    
                    //LOG_PATH = _runFolder + "sync_service.log";
                    //_log.WriteLine("LOG_PATH " + LOG_PATH);

                    //change _runFolder to point to folder containing logs, stats,running files
                    _runFolder = _runFolder + RUN_LOG_DIR;
                    _log.WriteLine("changed _runFolder " + _runFolder);
                }
                if (!Directory.Exists(_runFolder))
                {
                    _log.WriteLine("creating  " + _runFolder);
                    Directory.CreateDirectory(_runFolder);
                }
                lock (this)
                {
                    _initialized = true;
                }
            }
            else
            {
                _log.WriteLine("ERR: opening CONF_PATH :{0}", CONF_PATH);
            }
            
        }
        //====================================================================================================
        protected override void OnStop()
        {
            base.OnStop();
            
            //_stopperThread = new Thread(new ThreadStart(Stopper));
            //_stopperThread.Start();
            lock (this)
            {
                _run = 0;
            }
            Stopper();
            _log.WriteLine("on stop : " + DateTime.Now.ToShortDateString() + " " + DateTime.Now.ToShortTimeString());
            _log.WriteLine("==================================================================================================================");
            //_log.Flush();
            _log.Close();
        }
        //====================================================================================================
        protected override void OnContinue()
        {
            base.OnContinue();
            TextWriter tw = new StreamWriter("D:\\date.txt",true);
            tw.WriteLine("on cont : " + DateTime.Now.ToShortDateString() + " " + DateTime.Now.ToShortTimeString());
            tw.Close();
            
        }
        //====================================================================================================

        protected override void OnPause()
        {
            base.OnPause();
            TextWriter tw = new StreamWriter("D:\\date.txt",true);
            tw.WriteLine("on pause : " + DateTime.Now.ToShortDateString() + " " + DateTime.Now.ToShortTimeString());
            tw.Close();
            
        }
        //====================================================================================================

        protected override void OnShutdown()
        {
            base.OnShutdown();
            
        }
        
        //====================================================================================================

        protected void Worker()
        {
            init();

            XmlDocument doc = new XmlDocument();
            if (File.Exists(_jobsConfPath))
            {
                doc.Load(_jobsConfPath);
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

                    if(ignore.InnerText.Equals("1")){
                        _log.WriteLine("ignoring job {0}",idNode.InnerText);
                        continue;
                    }

                    XmlElement startNode = (XmlElement)item.GetElementsByTagName("start").Item(0);
                    XmlNodeList clientNodes = item.GetElementsByTagName("client");
                    XmlNodeList exclNodes = item.GetElementsByTagName("exclude");
                    XmlNodeList exclreNodes = item.GetElementsByTagName("exclude_re");
                    if (nameNode == null || idNode == null || masterNode == null || clientNodes.Count == 0 || startNode == null)
                    {
                        _log.WriteLine("WARN: job is missing essential info");
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
                        //_log.WriteLine("{0} {1} {2} {3} {4}", name, id, master, start, clients, excl, exclre);

                        SyncJob sj = new SyncJob(name, id, start, master, clients, excl, exclre);
                        _log.WriteLine(sj);
                        //_log.Flush();

                        //calculate delay period for first run
                        //if "start" time has passed today calculate the time for the following day, else calculate time for today.
                        DateTime dt = Convert.ToDateTime(start);
                        if (DateTime.Now.CompareTo(dt) > 0)
                        {
                            dt = dt.AddDays(1);
                        }
                        //int startDelay=(int) ((dt.Ticks - DateTime.Now.Ticks) / 10000000);
                        TimeSpan span1 = TimeSpan.FromSeconds((double)(dt.Ticks - DateTime.Now.Ticks) / 10000000);

                        lock (this)
                        {
                            //if(!_jobsMap.ContainsKey(start))
                            //{
                            //    _jobsMap.Add(start, sj);
                            //}

                            System.Threading.TimerCallback tcb = new System.Threading.TimerCallback(StartJobOnTime);

                            // start tcb with parameter SyncJob , duetime is span1 calculated earlier, repeat every 24hours

                            System.Threading.Timer t = new Timer(tcb, sj, span1, TimeSpan.FromSeconds(24*60*60));
                            _log.WriteLine("created timer for {0}: {1} ", span1, TimeSpan.FromSeconds(24 * 60 * 60));

                            //test  stuff
                            //System.Threading.Timer t = new Timer(tcb, sj, TimeSpan.FromSeconds(sj.Id), TimeSpan.FromSeconds(2000));
                            //_log.WriteLine("created timer for {0}: {1} ", TimeSpan.FromSeconds(sj.Id), TimeSpan.FromSeconds(2000));

                            _timers.AddLast(t);
                        }
                    }
                }//ended iterating through job elements
            }
            else
            {
                _log.WriteLine("ERR: opening jobs_conf :{0}", _jobsConfPath);
            }



            _log.WriteLine(DateTime.Now.ToShortDateString() + " " + DateTime.Now.ToShortTimeString());
            
        }

        //====================================================================================================
        //separate thread 
        private void StartJobOnTime(object state)//,System.Timers.ElapsedEventArgs args)
        {
            //Console.WriteLine("Hello World!{0}", state.ToString());
            //Thread.Sleep(10000);

            //check if it's activity file exists. if yes, skip.
            SyncJob sj = (SyncJob)state;

            _log.WriteLine("thread started :{0}: {1} {2}", sj.Id, DateTime.Now.ToShortDateString(), DateTime.Now.ToShortTimeString());

            foreach (KeyValuePair<String, String> pair in sj.Clients)
            {
                string[] filePaths = Directory.GetFiles(@_runFolder, sj.Id + "." + pair.Key + "*" + ".portfile");
                //if (filePaths.Length > 0)
                //{
                //    _log.WriteLine("already running.");
                //    continue;
                //}

                // we'll set this to false if we find a portfile modified less than 3 seconds ago
                Boolean shouldRun = true;
                foreach (string s in filePaths)
                {
                    FileInfo finf = new FileInfo(s);
                    if (DateTime.Now.Subtract(finf.LastWriteTime).TotalSeconds > _touchPortfileTime+1)
                    {
                        _log.WriteLine(s + " was modified {0} sec ago,ignore", DateTime.Now.Subtract(finf.LastWriteTime).TotalSeconds);
                        //_log.Flush();
                    }
                    else
                    {
                        _log.WriteLine(s+" is already running.");
                        shouldRun = false ;
                    }
                }
                if (!shouldRun)
                {
                    continue;
                }

                Process proc = new Process();
                ProcessStartInfo psInfo = new ProcessStartInfo(@"D:\Perl\bin\perl.exe");
                //psInfo.Arguments = @"D:\a\test1.pl" + " " + sj.Id + "_" + pair.Key;
                String args = @_syncScriptPath + " -s " + sj.Master + " -d " + pair.Value + " -sid " + sj.Id + " -did " + pair.Key + " -c 4 ";
                if (sj.Excl.Count > 0)
                {
                    args += " -excl ";
                    foreach (String s in sj.Excl)
                    {
                        args = args + s + ",";
                    }
                }
                if (sj.Exclre.Count > 0)
                {
                    args += " -exclre ";
                    foreach (String s in sj.Exclre)
                    {
                        args = args + s + ",";
                    }
                }
                if (_debug)
                {
                    args = args + " -v";
                }
                
                
                psInfo.Arguments = args;
                _log.WriteLine("Calling: "+psInfo.Arguments);
                //psInfo.Arguments = SYNC_PL_FILE + " -s " + @sj.Master + " -d " + @client + " -c 2";
                psInfo.UseShellExecute = true;
                //psInfo.RedirectStandardOutput = true;
                ////psInfo.WindowStyle = ProcessWindowStyle.Hidden;
                psInfo.CreateNoWindow = true;
                proc.StartInfo = psInfo;
                //proc.OutputDataReceived += new DataReceivedEventHandler();
                proc = Process.Start(psInfo);
                //proc.BeginOutputReadLine();

                _log.WriteLine("started {0} to {1}", sj.Id, pair.Key);
                //_log.Flush();
                //Console.WriteLine(SYNC_PL_FILE + " -s " + @sj.Master + " -d " + @client + " -c 2");
                Thread.Sleep(2000);
                //proc.Kill();

                lock (this)
                {
                    _procs.Add(proc);
                }
            }
        }

        //====================================================================================================
        //separate thread 
        private void ListenConfChange()
        {
            //listen on first available port then create service_running.port
            TcpListener listener=new TcpListener(IPAddress.Parse("127.0.0.1"),0);
            listener.Start();
            int port = ((IPEndPoint)listener.LocalEndpoint).Port;

            //while (_run==1)
            //{
            while (!_initialized)
            {
                Thread.Sleep(1);
            }
                _log.WriteLine("Listening on port {0}", port);
                
                //erase any running file if there is smth left in running_folder
                string[] filePaths = Directory.GetFiles(@_runFolder , "service_running*");
                foreach (string s in filePaths)
                {
                    _log.WriteLine("deleting "+s);
                    File.Delete(s);
                }
                
                _servRunningFile = _runFolder +"\\"+ "service_running." + port;
                _log.WriteLine("creating running file : {0}", _servRunningFile);
                File.Create(_servRunningFile);
                //_log.WriteLine("created running file : {0}", _servRunningFile);
                listener.Start();
                while (_run == 1)
                {
                    //blocks until a client has connected to the server
                    TcpClient client = listener.AcceptTcpClient();
                    _log.WriteLine("Accepted client");
                    NetworkStream clientStream = client.GetStream();
                    byte[] message = new byte[4096];
                    int bytesRead = clientStream.Read(message, 0, 4096);
                    String msj = new ASCIIEncoding().GetString(message, 0, bytesRead);
                    _log.WriteLine("received {0}", msj);
                    _reloadJobsConf();
                    client.Close();

                }
            //}
            listener.Stop();
        }
        //====================================================================================================
        private void _reloadJobsConf()
        {
            _log.WriteLine("Resetting all timers, had {0}",_timers.Count);
            _log.Close();
            //stop all timers
            foreach (Timer t in _timers)
            {
                t.Dispose();
            }
            _timers.Clear();
            Worker();
            _log.WriteLine("Created {0} timers.",_timers.Count);
        }
        //====================================================================================================
        //separate thread 
        private void Stopper()
        {
            //send msj 1 stop to all active processes ( by portfile)
            _log.WriteLine();
            _log.WriteLine("Sending msj1 (stop) to all portfiles,runfolder {0}", @_runFolder);

            Regex re = new Regex("\\.([0-9]+)\\.portfile");
            string[] filePaths = Directory.GetFiles(@_runFolder, "*portfile");
            foreach(string s in filePaths)
            {
                //_log.WriteLine(s);
                Match m = re.Match(s);
                if (m.Success)
                {
                    string port = m.Groups[1].Value;
                    _log.WriteLine(port);
                    FileInfo finf = new FileInfo(s);
                    if (DateTime.Now.Subtract(finf.LastWriteTime).TotalSeconds > _touchPortfileTime+1)
                    {
                        _log.WriteLine("modified {0} sec ago,ignore", DateTime.Now.Subtract(finf.LastWriteTime).TotalSeconds);
                        //_log.Flush();
                    }
                    else
                    {
                        //try to send msj 1 to port
                        try
                        {
                            Socket m_socClient = new Socket(AddressFamily.InterNetwork, SocketType.Stream, ProtocolType.IP);

                            System.Net.IPAddress ipAdd = System.Net.IPAddress.Parse("127.0.0.1");
                            System.Net.IPEndPoint remoteEP = new IPEndPoint(ipAdd, Int32.Parse(port));
                            m_socClient.Connect(remoteEP);
                            byte[] byData = System.Text.Encoding.ASCII.GetBytes("1");
                            m_socClient.Send(byData);
                            _log.WriteLine("sent msj1 to " + port);
                        }catch(Exception e){
                            _log.WriteLine(e);
                        }
                    }
                }
            }
        }
    }
}
