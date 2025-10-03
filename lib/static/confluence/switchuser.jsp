<%@ page import="com.atlassian.seraph.auth.DefaultAuthenticator" %>
<%@ page import="com.atlassian.confluence.user.ConfluenceUserManager" %>
<%@ page import="com.atlassian.spring.container.ContainerManager" %>
<%@ page import="com.atlassian.confluence.user.AuthenticatedUserThreadLocal" %>
<%@ page import="com.atlassian.sal.api.user.UserManager" %>
<%@ page import="com.atlassian.confluence.util.GeneralUtil"%>
<%@ page import="com.atlassian.confluence.security.PermissionManager" %>
<%@ page import="com.atlassian.confluence.user.ConfluenceUser" %>
<%
	// Temporarily become another user.
	// © 2018 Red Radish Consulting. Licensed per https://www.apache.org/licenses/LICENSE-2.0.html
	ConfluenceUser user = (ConfluenceUser) AuthenticatedUserThreadLocal.getUser();
	PermissionManager permissionManager = (PermissionManager) ContainerManager.getComponent("permissionManager");
	if (permissionManager.isSystemAdministrator(user))
	{
		String newUsername = request.getParameter("user");
		if (newUsername != null) {
			ConfluenceUser newUser =(ConfluenceUser) GeneralUtil.getUserAccessor().getUser(newUsername);
			if (newUser != null) {
				if (session.getAttribute("okta.confluence.user") != null) {
					session.setAttribute("okta.confluence.user", newUser);
				}
				session.setAttribute(DefaultAuthenticator.LOGGED_IN_KEY, newUser );
				// Tell websudo to get lost
				session.setAttribute("confluence.websudo.timestamp", System.currentTimeMillis());
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
	}  else {
		response.setStatus(403); // Forbidden
		out.println("Restricted to System Administrators");
	}
%>
