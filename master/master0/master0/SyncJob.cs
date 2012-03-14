using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;

namespace master0
{
    class SyncJob
    {
        private String _name;
        private int _id;
        private String _start;   // "11:10" 
        private String _master;
        private Dictionary<String, String> _clients;
        private HashSet<String> _excl; //exclude list containing only full file names
        private HashSet<String> _exclre;        //patterns 

        public SyncJob() { }
        public SyncJob(string name, int id, string start, string master, Dictionary<String, String> clients, HashSet<string> excl, HashSet<string> exclre)
        {
            _name = name;
            _id = id;
            _start = start;
            _master = master;
            _clients = clients;
            _excl = excl;
            _exclre = exclre;
        }

        public string Name
        {
            get { return _name; }
            set { _name = value; }
        }

        public int Id
        {
            get { return _id; }
            set { _id = value; }
        }

        public string Start
        {
            get { return _start; }
            set { _start = value; }
        }

        public string Master
        {
            get { return _master; }
            set { _master = value; }
        }

        public Dictionary<String, String> Clients
        {
            get { return _clients; }
            set { _clients = value; }
        }

        public HashSet<String> Excl
        {
            get { return _excl; }
            set { _excl = value; }
        }

        public HashSet<String> Exclre
        {
            get { return _exclre; }
            set { _exclre = value; }
        }

        public override string ToString()
        {
            string ret = Name + ", clients: ";
            foreach (KeyValuePair<String, String> pair in Clients)
            {
                ret += " " + pair.Value;
            }
            ret += ", excl: ";
            foreach (String ex in _excl)
            {
                ret += " " + ex;
            }
            ret += ", exclre: ";
            foreach (String ex in _exclre)
            {
                ret += " " + ex;
            }
            return ret;
        }
    }
}
