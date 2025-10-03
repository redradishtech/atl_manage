require 'sequel'
require 'xmlsimple'
require 'pathname'
require 'nokogiri'
require 'cgi'

module JIRADB

    class JIRADB

	ALL_ISSUE_TYPES = "All issue types"
	attr_accessor :baseurl

	def initialize(atlconfig)
		@atlconfig = atlconfig
	    @db = Sequel.connect(@atlconfig.dburl, :user =>  @atlconfig.user, :password => @atlconfig.password)
	    @baseurl = baseurl ||= @db["select ps.propertyvalue from propertyentry pe, propertystring ps where pe.id=ps.id and pe.property_key='jira.baseurl'"].first[:propertyvalue]
	end

	def status(id)
	    ds= @db[:issuestatus].filter(:id=>:$n)
	    ds.call(:select, :n => id.to_s).first
	end

	def event(id)
	    ds= @db[:jiraeventtype].filter(:id=>:$n)
	    ds.call(:select, :n => id).first
	end

	def customfield(id)
	    ds= @db[:customfield].filter(:id=>:$n)
	    ds.call(:select, :n => id.to_i).first
	end

	# Loops through each JIRA workflow, calling a block with |workflowid, workflowname, workflowdescriptor, self|
	# The 'self' is there so the caller can access our baseurl
	def eachworkflow()
	    #class Issue < Sequel::Model(:jiraissue)
	    #end
	    baseurl = @baseurl
	    @db.fetch("select id,workflowname,descriptor from jiraworkflows where workflowname in (select distinct workflow from workflowschemeentity where scheme in (select id from workflowscheme where id in (select sink_node_id from nodeassociation where sink_node_entity='WorkflowScheme')));").collect { |r|
		yield r[:id], r[:workflowname], r[:descriptor], self
	    }
	end

	def eachworkflowscreen(descriptor, screen) 
	    Nokogiri::XML(descriptor).xpath("//meta[@name='jira.fieldscreen.id' and text() = '#{screen}']").inject([]) { |c,x|
		statusid, sid, sn, aid, an = x.xpath("ancestor::step/meta[@name='jira.status.id']/text()").to_s, x.xpath("ancestor::step/@id"), x.xpath("ancestor::step/@name"), x.xpath("ancestor::action/@id"), x.xpath("ancestor::action/@name")
		if statusid=='' then statusid = nil; end
		funcxml = x.xpath('..')
		c << (yield statusid, sid, sn, aid, an, funcxml)
	    }
	end
	def eachworkflowfunction(descriptor, funcstr)
	    Nokogiri::XML(descriptor).xpath("//*[contains(text(),'#{funcstr}')]").inject([]) { |c,x|
		statusid, sid, sn, aid, an = x.xpath("ancestor::step/meta[@name='jira.status.id']/text()").to_s, x.xpath("ancestor::step/@id"), x.xpath("ancestor::step/@name"), x.xpath("ancestor::action/@id"), x.xpath("ancestor::action/@name")
		if statusid=='' then statusid = nil; end
		funcxml = x.xpath('..')
		c << (yield statusid, sid, sn, aid, an, funcxml)
	    }
	end

	def workflowprojectissuetype(wfname)
	    @db.fetch("select p.id::integer pid, p.pkey, p.pname, it.pname itname, it.id::integer itid, CASE WHEN pstyle='jira_subtask' THEN true ELSE false END issubtask, wfse.workflow from project p, workflowscheme wfs, nodeassociation na, workflowschemeentity wfse, (select * from issuetype UNION (select '0', null, '#{ALL_ISSUE_TYPES}', null, 'All issue types', null, null)) it where na.source_node_entity='Project' and p.id=na.source_node_id and  wfs.id=na.sink_node_id and na.sink_node_entity='WorkflowScheme' and wfse.scheme=wfs.id and it.id=wfse.issuetype  and wfse.workflow='#{wfname}' order by p.pkey, it.id;").all
	end

	def groups
	    @db.fetch("select id, group_name from cwd_group").collect { |r|
		yield r[:id].to_i, r[:group_name]
	    }
	end

	def db
	    @db
	end

	def user_make_member(userid, username, groupid, groupname)
	    alreadythere = @db.fetch("select count(*) from cwd_membership where parent_id=#{groupid} and child_id=#{userid}").single_value.to_i
	    if (alreadythere == 0) then
		count =  @db.fetch("select max(id) from cwd_membership").single_value.to_i
		count +=1
		puts "Inserting id #{count}"
		@db.run("insert into cwd_membership values (#{count}, #{groupid}, #{userid}, 'GROUP_USER', null, '#{groupname}', '#{groupname}', '#{username}', '#{username}', 2);")
		seqvalueid = @db.fetch("select seq_id from sequence_value_item where seq_name='Membership'").single_value.to_i
		if count >= seqvalueid then
		    newval = count + 10-(count % 10)
		    puts "Updating sequence_value_item to #{newval}"
		    @db.run("update sequence_value_item set seq_id=#{newval} where seq_name='Membership'")
		end
	    else
		puts "Skipping #{groupname}"
	    end 
	end

	def createsearchurl_forissuesinworkflow(statusname, wfname)
	    createsearchurl(statusname, workflowprojectissuetype(wfname).collect { |r| [r[:pkey], r[:itname]]  })
	end


	# Returns a search URL of all issues in the specified status and whose project uses the specified workflow
	# Params:
	#   statusname: eg. "Open" or "In Progress"
	#   proj_issuetypes: Array of [pkey, issuename]s, eg. [["ABC", "Bug"], ["TST", "Task"]]
	def createsearchurl(statusname, proj_issuetypes)
	    jql = ""

	    if statusname then
		jql = "status=\"#{statusname}\""
		jql += " AND " unless proj_issuetypes.empty? 
	    end # For Create transitions there is no status

	    if !proj_issuetypes.empty? then
		jql += "("
		jql += proj_issuetypes.collect { |pname, itname|
		    s="(project = #{pname}"
		    s+= " and issuetype = \"#{itname}\""  if itname != ALL_ISSUE_TYPES
		    s+=")"
		    s
		}.join " OR "
		jql += ")"
	    end
	    return baseurl+"/secure/IssueNavigator!executeAdvanced.jspa?reset=true&jqlQuery="+URI.escape(jql)
	end

	# Returns a list of fields and their screens whose fieldconfiguration may contain Javascript.
	def javascript_fields_and_screens
	    # Each Field Configuration (fieldlayout in the db) is a collection of fields, with each field (fieldlayoutitem) having an indication of required'ness, visibility, and a
	    # description string that may contain Javascript..
	    @db.fetch("SELECT CF.cfname, FS.name screenname, FS.id::integer
	    screenid, FSLI.fieldidentifier, FL.id::integer fieldlayoutid,
	    FL.name fieldlayoutname, FLI.description, FLI.id::integer scriptid
FROM        
	(select FLI.id, fieldidentifier, description, ishidden, isrequired, fieldlayout from fieldlayoutitem FLI group by id, fieldidentifier, description, ishidden, isrequired, fieldlayout) FLI
	LEFT OUTER JOIN customfield CF  ON substring(FLI.fieldidentifier, 13)=''||CF.id
	LEFT JOIN fieldlayout FL        ON      FL.id = FLI.fieldlayout
	JOIN fieldscreenlayoutitem FSLI         ON       FSLI.fieldidentifier = FLI.fieldidentifier
	JOIN fieldscreentab FST ON      FST.id = FSLI.fieldscreentab
	JOIN fieldscreen FS     ON      FS.id=FST.fieldscreen 
	WHERE FLI.description like '%<script%';").all.collect { |r| 
		[ r[:fieldidentifier], r[:cfname], r[:description], r[:screenid], r[:screenname], r[:scriptid], r[:fieldlayoutid], r[:fieldlayoutname] ]
	    }
	end

	# Return a list of [project, issuetype] pairs associated with the specified field configuration (field layout)
	def validprojectissuetypesforfieldlayout(fieldlayoutid)
	    @db.fetch("select P.id::integer pid, P.pkey, IT.id::integer itid, IT.pname itname from fieldlayout FL LEFT JOIN fieldlayoutschemeentity FLSE ON FL.id=FLSE.fieldlayout LEFT JOIN fieldlayoutscheme FLS ON FLS.id=FLSE.scheme LEFT JOIN nodeassociation NA  ON NA.sink_node_id=FLS.id LEFT JOIN project P ON P.id=NA.source_node_id LEFT JOIN issuetype IT ON IT.id=FLSE.issuetype WHERE NA.source_node_entity='Project' and NA.sink_node_entity='FieldLayoutScheme' and FL.id=#{fieldlayoutid}").all.collect{ |r| [r[:pkey], r[:itname]] }
	end
    end
end

