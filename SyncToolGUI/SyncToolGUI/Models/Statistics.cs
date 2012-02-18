using System;
using System.Collections.Generic;
using System.Linq;
using System.Web;

namespace SyncToolGUI.Models {
    public class ProcessStatistics {
        public ProcessStatistics(int processId, int filesScanned, 
            int filesAdded, int filesDeleted, int filesReplaced, int filesAltered, 
            int kbAdded, int runningTime, int errors, DateTime lastRun, 
            DateTime lastStatistics)
        {
           
            ProcessId = processId;
            FilesScanned = filesScanned;
            FilesAdded = filesAdded;
            FilesDeleted = filesDeleted;
            FilesReplaced = filesReplaced;
            FilesAltered = filesAltered;
            KBAdded = kbAdded;
            RunningTime = runningTime;
            Errors = errors;
            LastRun = lastRun;
            LastStatistics = lastStatistics;
        }

        public int ProcessId { get; set; }

        public int FilesScanned { get; set; }
        public int FilesAdded { get; set; }
        public int FilesDeleted { get; set; }
        public int FilesReplaced { get; set; }
        public int FilesAltered { get; set; }
        public int KBAdded { get; set; }
        public int RunningTime { get; set; }
        public int Errors { get; set; }
        public DateTime LastRun { get; set; }
        public DateTime LastStatistics { get; set; }
    }

    public class SyncJobStatistics {
        public List<ProcessStatistics> ProcessStatisticsList = new List<ProcessStatistics>();

    }
}