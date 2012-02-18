<%@ Page Title="" Language="C#" MasterPageFile="~/Views/Shared/Site.Master" Inherits="System.Web.Mvc.ViewPage<SyncToolGUI.Models.SyncJob>" %>

<asp:Content ID="Content1" ContentPlaceHolderID="TitleContent" runat="server">
    Details
</asp:Content>

<asp:Content ID="HeaderContent" ContentPlaceHolderID="HeaderContent" runat="server">
    <link href="/Content/Details.css" rel="stylesheet" type="text/css" />
</asp:Content>

<asp:Content ID="Content2" ContentPlaceHolderID="MainContent" runat="server">
    <div class="info_header">
        <div contenteditable="true">
            <%=Model.Name %></div>
        <div>
            Next run in : 12:12</div>
    </div>

    <div class="info_info">
        <div>
            <div>
                Master site:</div>
            <div>
                <%=Model.Master %></div>
        </div>
        <div>
            <div>
                Start time:</div>
            <div>
                <%=Model.Start %></div>
        </div>
        <div>
            <div>
                Master site:</div>
            <div>
                <input type="checkbox" checked="<%=Model.Ignore %>"></input>Ignore</div>
        </div>
    </div>

    <div class="info_clients">
        <ul>
            <% foreach (var item in Model.Clients) { %>
            <li>
                <%=item.Value %></li>
            <%  } %>
        </ul>
    </div>

    <div class="info_ignore">
        <div class="ignore_words">
            <h3>Exclude Paths</h3>
            <ul>
                <% foreach (var item in Model.Excl) { %>
                <li>
                    <%=item %></li>
                <%  } %>
            </ul>
        </div>

        <div class="ignore_expr">
            <h3>Exclude Expressions</h3>
            <ul>
                <% foreach (var item in Model.Exclre) { %>
                <li>
                    <%=item %></li>
                <%  } %>
            </ul>
        </div>
    </div>
</asp:Content>
