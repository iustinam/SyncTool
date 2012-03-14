using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading;
using System.Timers;
using System.Xml;
using Timer = System.Threading.Timer;

namespace test
{
    class Program
    {
        private Dictionary<DateTime, String> jobsMap = new Dictionary<DateTime, string>();
        public const String CONF_FILE = "D:\\sync\\conf.xml";
        private static HashSet<Timer> _jobTimers=new HashSet<Timer>();

        static void PrintTime(object state)
        {
            Console.WriteLine("Time is: {0}, Param is: {1}", DateTime.Now.ToLongTimeString(), state.ToString());
            Console.ReadKey();
        }
        static void Main(string[] args)
        {
            SysTimers();
        }

        private static void StartJobOnTime(object source)//, ElapsedEventArgs e)
        {
            Console.WriteLine("Hello World!{0}",source.ToString());
            Thread.Sleep(10000);
           
        }
        public static void  SysTimers()
        {
            for (int i = 0; i < 10; i++)
            {
                //System.Timers.Timer aTimer = new System.Timers.Timer();
                //aTimer.Elapsed += new ElapsedEventHandler(StartJobOnTime);
                //// Set the Interval to 1 day
                //aTimer.Interval = 6;
                //aTimer.AutoReset = true; 
                //aTimer.Enabled = true;
                
                //_jobTimers.Add(aTimer);

                System.Threading.TimerCallback tcb = new System.Threading.TimerCallback(StartJobOnTime);
                System.Threading.Timer t=new Timer(tcb,i,2000,10000);
                _jobTimers.Add(t);
            }
            Console.WriteLine("Press Enter to exit");
            int j = Console.Read();
            
            //Console.WriteLine(_jobTimers.Count);
            // clean up the resources
            for (int k = 0; k < 10; k++)
            {
                _jobTimers.ElementAt(k).Dispose();
            }
        }

        public void xml()
        {
            XmlDocument doc = new XmlDocument();
            if (File.Exists(CONF_FILE))
            {
                doc.Load(CONF_FILE);
                XmlElement elem = doc.DocumentElement;

                String name, master, start;
                HashSet<String> clients = new HashSet<string>();
                foreach (XmlElement item in elem.ChildNodes)
                {

                    XmlElement nameNode = (XmlElement)item.GetElementsByTagName("name").Item(0);
                    XmlElement masterNode = (XmlElement)item.GetElementsByTagName("master").Item(0);
                    XmlElement startNode = (XmlElement)item.GetElementsByTagName("start").Item(0);
                    XmlNodeList clientNodes = item.GetElementsByTagName("client");
                    if (nameNode == null || masterNode == null || clientNodes.Count == 0 || startNode == null)
                    {
                        Console.WriteLine("something missing from job conf");
                    }
                    else
                    {
                        name = nameNode.InnerText;
                        start = startNode.InnerText;
                        master = masterNode.InnerText;
                        foreach (XmlElement cli in clientNodes)
                        {
                            clients.Add(cli.InnerText);
                            Console.WriteLine(cli.InnerText);
                        }

                        Console.ReadKey();
                        //jobsMap.Add(.ToString(),);
                    }


                }

            }
            else
            {
                Console.WriteLine("Conf file missing");
            }
        }

        public void proc()
        {
            Process proc=new Process();
            ProcessStartInfo psInfo= new ProcessStartInfo(@"D:\Perl\bin\perl.exe");
            psInfo.Arguments = @"D:\a\perlservicetest.pl";
            psInfo.UseShellExecute = false;
            psInfo.RedirectStandardOutput = true;
            psInfo.WindowStyle=ProcessWindowStyle.Hidden;
            psInfo.CreateNoWindow = true;
            proc.StartInfo = psInfo;
            //proc.OutputDataReceived += new DataReceivedEventHandler();
            proc.Start();
            proc.BeginOutputReadLine(); 
        }
        
        public static void Proc1()
        {
            ProcessStartInfo psInfo = new ProcessStartInfo(@"D:\Perl\bin\perl.exe");
            psInfo.Arguments = @"D:\a\perlservicetest.pl";
            psInfo.UseShellExecute = false;
            psInfo.RedirectStandardOutput = true;
            psInfo.WindowStyle = ProcessWindowStyle.Hidden;
            psInfo.CreateNoWindow = true;
            Process.Start(psInfo);

        }

        public void timerthr()
        {
            
          //TimerCallback timeCB = new TimerCallback(PrintTime);

          //  Timer t = new Timer(
          //      timeCB,   // The TimerCallback delegate type.
          //      "Hi",     // Any info to pass into the called method.
          //      0,        // Amount of time to wait before starting.
          //      1000);    // Interval of time between calls. 

          //  Timer t = new Timer(
          //      timeCB,   // The TimerCallback delegate type.
          //      "Hi",     // Any info to pass into the called method.
          //      0,        // Amount of time to wait before starting.
          //      1000);    // Interval of time between calls. 
        }
    }
}
