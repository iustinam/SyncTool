using System;
using System.Collections.Generic;
using System.Linq;
using System.Web;
using System.Web.Mvc;
using SyncToolGUI.Models;

namespace SyncToolGUI.Controllers {
    public class SyncJobsController : Controller {
        private SyncJobsParser _parser = SyncJobsParser.Instance;

        // GET: /SyncJobs/

        public ActionResult Index() {
            List<SyncJob> jobs = _parser.GetAllSyncJobs();
            return View(jobs);
        }

        //GET: /SyncJobs/Details/1
        public ActionResult Details(int id) {
            SyncJob job = _parser.GetJob(id);
            return View(job);
        }

        public ActionResult WatchJob(int id) {
            SyncJob job = _parser.GetJob(id);
            return View(job);
        }

        public ActionResult GetStatistics(int id) {
            /*return Json(new SyncJobStatistics() {
                ProcessStatistics = new List<ProcessStatistics>(){
                     new ProcessStatistics(){
                         Errors=1,FilesAdded=3
                }
                }
            },JsonRequestBehavior.AllowGet);
             */
            ProcessManager pm = new ProcessManager();
            SyncJobStatistics sjStats= pm.GetStatisticsForJob(id);
            return Json(sjStats,JsonRequestBehavior.AllowGet);
        }

    }
}
