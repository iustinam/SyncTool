<%@ Page Title="" Language="C#" MasterPageFile="~/Views/Shared/Site.Master" Inherits="System.Web.Mvc.ViewPage<SyncToolGUI.Models.SyncJob>" %>

<asp:Content ID="Content1" ContentPlaceHolderID="TitleContent" runat="server">
	WatchJob  <%=Model.Master %>
</asp:Content>

<asp:Content ID="Content2" ContentPlaceHolderID="MainContent" runat="server">

    <div class="main_header">
        <h2><%=Model.Master %></h2>
        <button>Start All</button>
        <button>Stop All</button>
    </div>

    <% foreach (var item in Model.Clients) { %>
        <div class="process">
            <table class="process_header">
                <tr>
                    <td class="process_name"><%=item.Value %></td>
                
                    <td class="state">State: <span class="state_off" id="<%=item.Key %>_running">stopped</span></td>

                    <td class="process_buttons_start">
                        <button>Start</button>
                        <button>Stop</button>
                    </td>
                
                    <td class="process_buttons_stats">
                        <button>View Last Log</button>
                        <button>View Last Statistics</button>
                    </td>
                </tr>
            </table>
            <div class="stats">
                <table>
                    <tr>
                        <td>Files Scanned</td>
                        <td  id="<%=item.Key %>_fs">0</td>
                        <td>KB Added</td>
                        <td  id="<%=item.Key %>_kba">0</td>
                    </tr>
                    <tr>
                        <td>Files Added</td>
                        <td  id="<%=item.Key %>_fa">0</td>
                        <td>Running Time</td>
                        <td  id="<%=item.Key %>_rt">0</td>
                    </tr>
                    <tr>
                        <td>Files Deleted</td>
                        <td  id="<%=item.Key %>_fd">0</td>
                        <td>Errors</td>
                        <td  id="<%=item.Key %>_err">0</td>
                    </tr>
                    <tr>
                        <td>Files Replaced</td>
                        <td  id="<%=item.Key %>_fr">0</td>
                        <td>Last Run</td>
                        <td  id="<%=item.Key %>_lr">0</td>
                    </tr>
                    <tr>
                        <td>Files Altered</td>
                        <td  id="<%=item.Key %>_fal">0</td>
                        <td>Last Statistics</td>
                        <td  id="<%=item.Key %>_ls">0</td>
                    </tr>
                </table>
            </div>
        </div>
           
    <%   } %>
    


</asp:Content>

<asp:Content ID="Content3" ContentPlaceHolderID="HeaderContent" runat="server">
    <link href="/Content/Watch.css" rel="stylesheet" type="text/css" />

    <script src="/Scripts/jquery-1.4.1.min.js" type="text/javascript"></script>
    <script src="/Scripts/Stats.js" type="text/javascript"></script>

    <script type="text/javascript">
        $(document).ready(function () {
            document.jobId = <%=Model.Id %>;
            document.jobs = [];
            
            <% foreach (var item in Model.Clients)
               { %>
                document.jobs.push(<%=item.Key %>)
            <% } %>

            startup();
        });
    </script>
</asp:Content>
