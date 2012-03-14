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
        private const String DEFAULT_CONF_PATH = @"D:\_eclipse\conf.xml";        
        private const String DEFAULT_SERVICE_LOG_PATH = @"C:\SyncTool\sync_service.log";

        private string _confPath;   //contains the paths to every component
        private String _serviceLogPath;
        private String _jobsConfPath;          //jobs conf file
        private String _syncScriptPath;        //sync.pl path
        private String _perlPath;
        private String _backupsDir;
        private String _logDir;
        private String _smtpServer=null;

        private String _portfileDir;//= "Logs";  //

        private String _serviceRunningFile;
        private int _touchPortfileTime=3;

        TextWriter _log;
        private HashSet<Process> _procs; //processes to kill when stopping the service
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
            // take paths from file : -conf as parameter or default 
            // if not -conf , log to default path this fact
            // if -conf, but file does not exist , log to default path and crash.

            //open log
            //if (!File.Exists(serviceLogPath))
            //{
            //    if (!Directory.Exists(LOG_DIR))
            //        Directory.CreateDirectory(LOG_DIR);
            //    File.Create (serviceLogPath);
            //}
            //_log = new StreamWriter(serviceLogPath, true);
            //((StreamWriter)_log).AutoFlush = true;
            //_log.WriteLine("==================================================================================================================");
            //_log.WriteLine("opened " + DateTime.Now.ToShortDateString() + " " + DateTime.Now.ToShortTimeString());

            StringBuilder tempLog = new StringBuilder();
            tempLog.AppendLine("==================================================================================================================");
            tempLog.AppendLine("opened: "+ DateTime.Now.ToShortDateString() + " " + DateTime.Now.ToShortTimeString());

            bool okParams = true;
            if (_args.Count() > 0)
            {
                tempLog.AppendLine("args:");
                for (int i = 0; i < _args.Count(); i++)
                {
                    tempLog.AppendLine(_args[i]);
                    if (_args[i].Equals("-debug"))
                    {
                        _debug = true;
                    }
                    if (_args[i].Equals("-conf"))
                    {

                        if (!(_args.Count() > i + 1))
                        {
                            tempLog.AppendLine("ERROR: invalid args, give the conf path after -conf");
                            okParams = false;
                        }
                        if (okParams && (!File.Exists(_args[i + 1])))
                        {
                            tempLog.AppendLine("ERROR: invalid '-conf' parameter : Path does not exist. Stopping.");
                            okParams = false;
                        }
                        if (okParams)
                        {
                            this._confPath = _args[i + 1];
                            tempLog.AppendLine("Configuration file path: " + this._confPath);
                            i++;
                        }
                    }
                }
            }
            else{
                okParams = false;
            }

            if (!okParams)
            {   //stop if conf invalid, send log default service log path 
                string dir = Path.GetDirectoryName(DEFAULT_SERVICE_LOG_PATH);
                if (!Directory.Exists(dir))
                {
                    Directory.CreateDirectory(dir);
                }
                if (!File.Exists(DEFAULT_SERVICE_LOG_PATH))
                {
                    File.Create(DEFAULT_SERVICE_LOG_PATH);
                }
                _log = new StreamWriter(DEFAULT_SERVICE_LOG_PATH, true);
                _log.Write(tempLog.ToString());
                _log.Flush();
                return;

            }

            //get paths 
            XmlDocument doc = new XmlDocument();
            doc.Load(this._confPath);
            XmlElement elem = doc.DocumentElement; //<conf>
            lock (this)
            {
                //should exist : running_folder,jobs_conf_filename,sync_path
                //if not there, create paths for: serviceLogFile,portfiles,logs_folder
                //warn if no : email_server ( or if unreachable)
                string runFolder=null;

                XmlElement tmpElem = (XmlElement)elem.GetElementsByTagName("running_folder").Item(0);
                bool ok = true; //running folder should exist because it contains the script and configurations
                if (tmpElem != null){
                    runFolder = tmpElem.InnerText;
                    if (!Directory.Exists(runFolder))
                    {
                        ok = false;
                        tempLog.AppendLine("ERROR: " + _confPath + " 'running_folder': invalid directory " + runFolder);
                    }
                    else
                        tempLog.AppendLine("running folder: " + runFolder);    //ok
                }
                else{
                    tempLog.AppendLine("ERROR: " + _confPath + " does not contain element 'running_folder'");
                    ok = false;
                }
                if (!ok)   //STOP service and write to default log 
                {
                    string dir = Path.GetDirectoryName(DEFAULT_SERVICE_LOG_PATH);
                    if (!Directory.Exists(dir))
                    {
                        Directory.CreateDirectory(dir);
                    }
                    if (!File.Exists(DEFAULT_SERVICE_LOG_PATH))
                    {
                        File.Create(DEFAULT_SERVICE_LOG_PATH);
                    }
                    _log = new StreamWriter(DEFAULT_SERVICE_LOG_PATH, true);
                    _log.Write(tempLog.ToString());
                    _log.Flush();
                    return;
                }

                //_serviceLogPath ... if not specified in conf, use the default
                tmpElem = (XmlElement)elem.GetElementsByTagName("serviceLogFile").Item(0);
                if (tmpElem == null)
                {  //use DEFAULT_SERVICE_LOG_PATH
                    _serviceLogPath = DEFAULT_SERVICE_LOG_PATH;
                }
                else
                {
                    _serviceLogPath=Path.Combine(@runFolder, tmpElem.InnerText);
                }

                if (!File.Exists(_serviceLogPath))
                {
                    File.Create(_serviceLogPath);
                }
                _log = new StreamWriter(_serviceLogPath, true);
                ((StreamWriter)_log).AutoFlush = true;
                _log.Write(tempLog.ToString());


                tmpElem = (XmlElement)elem.GetElementsByTagName("sync_path").Item(0);
                if (tmpElem == null)    //  die if no sync script path or if invalid
                {
                    _log.WriteLine("ERROR: " + _confPath + " does not contain element 'sync_path'");
                    return;
                }
                else
                {
                    _syncScriptPath = Path.Combine(@runFolder, tmpElem.InnerText);
                    if (!File.Exists(_syncScriptPath))
                    {
                        _log.WriteLine("ERROR: " + _confPath + " 'sync_path': invalid path " + _syncScriptPath);
                        return;
                    }
                    _log.WriteLine("_syncScriptPath " + _syncScriptPath);
                }

                tmpElem = (XmlElement)elem.GetElementsByTagName("jobs_conf_filename").Item(0);
                if (tmpElem == null)
                {
                    _log.WriteLine("ERROR: " + _confPath + " does not contain element 'jobs_conf_filename'");
                    return;
                }
                else
                {
                    _jobsConfPath = Path.Combine(@runFolder, tmpElem.InnerText);
                    if (!File.Exists(_jobsConfPath))
                    {
                        _log.WriteLine("ERROR: " + _confPath + " 'jobs_conf_filename': invalid path " + _jobsConfPath);
                        return;
                    }
                    _log.WriteLine("_jobsConfPath " + _jobsConfPath);
                }

                tmpElem = (XmlElement)elem.GetElementsByTagName("perl_path").Item(0);
                if (tmpElem == null)
                {
                    _log.WriteLine("ERROR: " + _confPath + " does not contain element 'perl_path'");
                    return;
                }
                else
                {
                    _perlPath = tmpElem.InnerText;
                    if (!File.Exists(_perlPath))
                    {
                        _log.WriteLine("ERROR: " + _confPath + " 'perl_path': invalid path " + _perlPath);
                        return;
                    }
                    _log.WriteLine("_perlPath " + _perlPath);
                }

                //log, backup and porfiles folders
                string dirname;
                tmpElem = (XmlElement)elem.GetElementsByTagName("portfiles").Item(0);
                if (tmpElem == null)
                    dirname = "run";
                else
                    dirname = tmpElem.InnerText;
                _portfileDir = Path.Combine(@runFolder, dirname);
                if (!Directory.Exists(_portfileDir))
                    Directory.CreateDirectory(_portfileDir);
                _log.WriteLine("_portfileDir " + _portfileDir);

                tmpElem = (XmlElement)elem.GetElementsByTagName("bkp_folder").Item(0);
                if (tmpElem == null)
                    dirname = "bkp";
                else
                    dirname = tmpElem.InnerText;
                _backupsDir = Path.Combine(@runFolder, dirname);
                if (!Directory.Exists(_backupsDir))
                    Directory.CreateDirectory(_backupsDir);
                _log.WriteLine("_backupsDir " + _backupsDir);

                tmpElem = (XmlElement)elem.GetElementsByTagName("logs_folder").Item(0);
                if (tmpElem == null)
                    dirname = "Logs";
                else
                    dirname = tmpElem.InnerText;
                _logDir = Path.Combine(@runFolder, dirname);
                if (!Directory.Exists(_logDir))
                    Directory.CreateDirectory(_logDir);
                _log.WriteLine("_logDir " + _logDir);

                tmpElem = (XmlElement)elem.GetElementsByTagName("touch_portfile_time").Item(0);
                if (tmpElem != null)
                    _touchPortfileTime = Int32.Parse(tmpElem.InnerText);
                _log.WriteLine("_touchPortfileTime " + _touchPortfileTime);

                //SMTP 
                tmpElem = (XmlElement)elem.GetElementsByTagName("email_server").Item(0);
                if (tmpElem != null)
                {
                    _smtpServer = tmpElem.InnerText;
                    _log.WriteLine("_smtpServer " + _smtpServer);
                }
                else
                {
                    _log.WriteLine("!! Warning: " + _confPath + " does not contain element 'email_server'");        
                }
                

                _initialized = true;
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
            if(_initialized)
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
            if (!_initialized)
            {
                //this.OnStop();
                this.Stop();
                return;
                //Environment.Exit(0);
            }
                
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
                    HashSet<String> mails = new HashSet<string>();

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
                    XmlNodeList mailNodes = item.GetElementsByTagName("email");

                    if (nameNode == null || idNode == null || masterNode == null || clientNodes.Count == 0 
                        || startNode == null)
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
                        foreach (XmlElement ex in mailNodes)
                        {
                            mails.Add(ex.InnerText);
                        }
                        //_log.WriteLine("{0} {1} {2} {3} {4}", name, id, master, start, clients, excl, exclre);

                        SyncJob sj = new SyncJob(name, id, start, master, clients, excl, exclre, mails);
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

                            //System.Threading.Timer t = new Timer(tcb, sj, span1, TimeSpan.FromSeconds(24 * 60 * 60));
                            //_log.WriteLine("created timer for {0}: {1} ", span1, TimeSpan.FromSeconds(24 * 60 * 60));

                            //test  stuff
                            System.Threading.Timer t = new Timer(tcb, sj, TimeSpan.FromSeconds(sj.Id), TimeSpan.FromSeconds(2000));
                            _log.WriteLine("created timer for {0}: {1} ", TimeSpan.FromSeconds(sj.Id), TimeSpan.FromSeconds(2000));

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
                string[] filePaths = Directory.GetFiles(@_portfileDir, sj.Id + "." + pair.Key + "*" + ".portfile");
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
                //ProcessStartInfo psInfo = new ProcessStartInfo(@"D:\Perl\bin\perl.exe");
                ProcessStartInfo psInfo = new ProcessStartInfo(@_perlPath);
                //psInfo.Arguments = @"D:\a\test1.pl" + " " + sj.Id + "_" + pair.Key;
                StringBuilder args = new StringBuilder(@_syncScriptPath + " -s \"" + sj.Master + "\" -d \"" + pair.Value + "\" -sid " + sj.Id + " -did " + pair.Key + 
                    " -usethr -conf "+_confPath);
                if (sj.Excl.Count > 0)
                {
                    args.Append(" -excl ");
                    foreach (String s in sj.Excl)
                    {
                        args.Append(s + ",");
                    }
                }
                if (sj.Exclre.Count > 0)
                {
                    args.Append(" -exclre ");
                    foreach (String s in sj.Exclre)
                    {
                        args.Append(s + ",");
                    }
                }
                if((sj.Mails.Count>0)&&(this._smtpServer!=null)){
                    args.Append(" -smtp "+_smtpServer);
                    args.Append(" -mailto ");
                    foreach (String s in sj.Mails)
                    {
                        args.Append(s + ",");
                    }
                }
                if (_debug)
                {
                    args.Append(" -v");
                }
                
                
                psInfo.Arguments = args.ToString();
                _log.WriteLine("Calling: \n"+psInfo.Arguments);
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
                string[] filePaths = Directory.GetFiles(@_portfileDir , "service_running*");
                foreach (string s in filePaths)
                {
                    _log.WriteLine("deleting "+s);
                    try
                    {
                        File.Delete(s);
                    }
                    catch (Exception e)
                    {
                        _log.WriteLine(e.ToString());
                    }
                }
                
                _serviceRunningFile = Path.Combine(@_portfileDir,"service_running." + port);
                _log.WriteLine("creating running file : {0}", _serviceRunningFile);
                File.Create(_serviceRunningFile);
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
            _log.WriteLine("Sending msj1 (stop) to all portfiles,runfolder {0}", @_portfileDir);

            Regex re = new Regex("\\.([0-9]+)\\.portfile");
            string[] filePaths = Directory.GetFiles(@_portfileDir, "*portfile");
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
