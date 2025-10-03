<%@ page import="com.atlassian.jira.ComponentManager" %>
<%@ page import="com.atlassian.jira.security.JiraAuthenticationContext" %>
<%@ page import="com.atlassian.seraph.auth.DefaultAuthenticator" %>
<%@ page import="com.atlassian.jira.user.util.UserManager" %>
<%@ page import="com.atlassian.jira.component.ComponentAccessor" %>
<%@ page import="com.atlassian.jira.permission.GlobalPermissionKey" %>
<%@ page import="com.atlassian.jira.security.Permissions" %>
<%@ page import="com.atlassian.jira.security.GlobalPermissionManager" %>
<%@ page import="com.atlassian.jira.user.ApplicationUser" %>
<%
	// Temporarily become another user.
	// © 2018 Red Radish Consulting. Licensed per https://www.apache.org/licenses/LICENSE-2.0.html
	// TODO: wrap this in a gadget: https://bitbucket.org/redradish/jira-sample-rest-gadget/src
	final JiraAuthenticationContext jiraAuthenticationContext = ComponentManager.getComponentInstanceOfType(JiraAuthenticationContext.class);
	ApplicationUser user = jiraAuthenticationContext.getLoggedInUser();
	 GlobalPermissionManager globalPermissionManager = ComponentAccessor.getGlobalPermissionManager();
	if (globalPermissionManager.hasPermission(GlobalPermissionKey.SYSTEM_ADMIN, user))
	{
		String newUsername = request.getParameter("user");
		if (newUsername != null) {
			UserManager userManager = ComponentAccessor.getUserManager();
			Object newUser = userManager.getUser(newUsername);
			if (newUser != null) {
				if (session.getAttribute("okta.jira.user") != null) {
					session.setAttribute("okta.jira.user", newUser);
				}
				session.setAttribute(DefaultAuthenticator.LOGGED_IN_KEY, newUser );
				// Tell websudo to get lost
				session.setAttribute("jira.websudo.timestamp", System.currentTimeMillis());
				String gotoPage = request.getParameter("goto");
				if (gotoPage != null) {
					response.sendRedirect(gotoPage);
				} else {
					response.sendRedirect("/");
				}
			} else {
				// TODO: wrap in webwork stuff so we can print the entered username without risking XSS
				out.println("<div class='aui-message aui-message-error'>No such user</div>");
			}
		}
		out.println("<form>Switch to user: <input name='user'/><br/>If successful, go to page: <input name='goto' value='/' /><input type='submit'/></form>");
	} else {
		response.setStatus(403); // Forbidden
		out.println("Restricted to System Administrators");
	}
%>
