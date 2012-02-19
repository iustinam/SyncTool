function startup() {
    window.setInterval(fetchStatistics, 500);
}

function fetchStatistics() {
    $.ajax({
        url: "/SyncJobs/getstatistics/" + document.jobId,
        dataType: "json",
        type: "GET",
        success: function (data) {
            parseStatistics(data);
        }
    });
}

function parseStatistics(data) {
    /*resetam toate joburile ca fiind oprite*/
    for (var j in document.jobs) {
        var elem = $("#" + document.jobs[j] + "_running");

        elem.text("stopped");
        elem.attr("class", "state_off");
    }

    for (var pi in data.ProcessStatisticsList) {
        parseProcess(data.ProcessStatisticsList[pi]);
    }
}

function parseProcess(data) {
    var elem = $("#" + data.ProcessId  + "_running");

    elem.text("running");
    elem.attr("class", "state_on");

    $("#" + data.ProcessId + "_fs").text(data.FilesScanned);
    $("#" + data.ProcessId + "_fa").text(data.FilesAdded);
    $("#" + data.ProcessId + "_fd").text(data.FilesDeleted);
    $("#" + data.ProcessId + "_fr").text(data.FilesReplaced);
    $("#" + data.ProcessId + "_fal").text(data.FilesAltered);

    $("#" + data.ProcessId + "_kba").text(data.KBAdded);
    $("#" + data.ProcessId + "_rt").text(data.RunningTime);
    $("#" + data.ProcessId + "_err").text(data.Errors);
    $("#" + data.ProcessId + "_lr").text(data.LastRun);
    $("#" + data.ProcessId + "_ls").text(data.LastStatistics);
}