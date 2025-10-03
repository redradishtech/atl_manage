#!/usr/bin/env ruby
#
require 'pp'
require 'set'
require 'pathname'
require 'pry'
require 'pry-byebug'
require 'open3'

def log(msg)
	$stderr.puts "****** " + msg
end

def assert &block
    binding.pry unless yield
end

## For commits we'll have HG_NODE, and for updates we'll have HG_PARENT1
commit_id = ENV['HG_NODE'] || ENV['HG_PARENT1']
assert { commit_id }

if !commit_id.include? `hg id`.split.first then
	log "Warning: batch-applying. The ACLs applied to this commit's files may have been set by later ACL files. Also, the files may have been renamed or deleted by later patches"
	exit
end
Pathname.new(".acl").glob("*") .each {  |aclfile|
	log  "Setting ACL #{aclfile}"
	stdout, status = Open3.capture2('setfacl', '--restore', aclfile.to_s)
	assert { status.success? }
	puts stdout
}
