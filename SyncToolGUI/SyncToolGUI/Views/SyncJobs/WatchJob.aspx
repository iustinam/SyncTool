<%@ Page Title="" Language="C#" MasterPageFile="~/Views/Shared/Site.Master" Inherits="System.Web.Mvc.ViewPage<SyncToolGUI.Models.SyncJob>" %>

<asp:Content ID="Content1" ContentPlaceHolderID="TitleContent" runat="server">
	WatchJob  <%=Model.Master %>
</asp:Content>

<asp:Content ID="Content2" ContentPlaceHolderID="MainContent" runat="server">

    <div>
        <h2><%=Model.Master %></h2>
        <button>Start All</button>
        <button>Stop All</button>
    </div>

    <% foreach (var item in Model.Clients) { %>
        <div>
            <div><%=item.Value %></div>
            <div>State: <div id="<%=item.Key %>_running"></div></div>
            <button>Start</button>
            <button>Stop</button>
            <button>View Last Log</button>
            <button>View Last Statistics</button>
        </div>
        <div>
            <table>
                <tr>
                    <td>Files Scanned</td>
                    <td>0</td>
                    <td>KB Added</td>
                    <td>0</td>
                </tr>
                <tr>
                    <td>Files Added</td>
                    <td>0</td>
                    <td>Running Time</td>
                    <td>0</td>
                </tr>
                <tr>
                    <td>Files Deleted</td>
                    <td>0</td>
                    <td>Errors</td>
                    <td>0</td>
                </tr>
                <tr>
                    <td>Files Replaced</td>
                    <td>0</td>
                    <td>Last Run</td>
                    <td>0</td>
                </tr>
                <tr>
                    <td>Files Altered</td>
                    <td>0</td>
                    <td>Last Statistics</td>
                    <td>0</td>
                </tr>
            </table>
        </div>
           
    <%   } %>
    


</asp:Content>

<asp:Content ID="Content3" ContentPlaceHolderID="HeaderContent" runat="server">
</asp:Content>
