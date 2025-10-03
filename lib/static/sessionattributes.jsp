<%@ page session="true" import="java.util.*" %>
<h1>Session attributes</h1>
<%
Enumeration keys = session.getAttributeNames();

out.println("Session ID: " + session.getId() + "<br>");
out.println("Max Inactive Interval: " + session.getMaxInactiveInterval() + "<br>");
while (keys.hasMoreElements())
{
  String key = (String)keys.nextElement();
  out.println(key + ": " + session.getValue(key) + "<br>");
}
%>
