using System;
using System.Collections.Generic;
using System.Linq;
using System.Web;

namespace SyncToolGUI.Models
{
    public class SyncJob
    {
        public String Name { get; set; }
        public int Id { get; set; }
        public String Start { get; set; }   // "11:10" 
        public String Master { get; set; }
        public Dictionary<String, String> Clients { get; set; }
        public HashSet<String> Excl { get; set; } //exclude list containing only full file names
        public HashSet<String> Exclre { get; set; }        //patterns 
        public bool Ignore { get; set; }

        public SyncJob() { }
        public SyncJob(string name, int id, string start, string master, Dictionary<String, String> clients, HashSet<string> excl, HashSet<string> exclre)
        {
            Name = name;
            Id = id;
            Start = start;
            Master = master;
            Clients = clients;
            Excl = excl;
            Exclre = exclre;
        }
    }
}