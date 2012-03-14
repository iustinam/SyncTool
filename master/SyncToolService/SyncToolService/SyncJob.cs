using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;

namespace master0
{
    class SyncJob
    {
        public String Name { get; set; }
        public int Id { get; set; }
        public String Start { get; set; }   // "11:10" 
        public String Master { get; set; }
        public Dictionary<String, String> Clients { get; set; }
        public HashSet<String> Excl { get; set; } //exclude list containing only full file names
        public HashSet<String> Exclre { get; set; }        //patterns 
        public HashSet<String> Mails { get; set; }

        public SyncJob() { }
        public SyncJob(string name, int id, string start, string master, Dictionary<String, String> clients,
            HashSet<string> excl, HashSet<string> exclre, HashSet<String> mails)
        {
            Name = name;
            Id = id;
            Start = start;
            Master = master;
            Clients = clients;
            Excl = excl;
            Exclre = exclre;
            Mails = mails;
        }

        public override string ToString()
        {
            StringBuilder ret = new StringBuilder();
            ret.AppendLine("--------------------------------------");
            ret.Append(Name +", clients: ");
            foreach (KeyValuePair<String, String> pair in Clients)
            {
                ret.Append( " " + pair.Value);
            }
            ret.Append(", excl: ");
            foreach (String ex in Excl)
            {
                 ret.Append(" " + ex);
            }
             ret.Append(", exclre: ");
            foreach (String ex in Exclre)
            {
                 ret.Append(" " + ex);
            }
            ret.AppendLine();
            return ret.ToString();
        }
    }
}
