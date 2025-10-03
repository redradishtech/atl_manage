#!/usr/bin/env ruby

require 'pry'
require 'pry-byebug'

s="""
# file: nagios
# owner: jturner
# group: jturner
user::rwx
user:root:r-x
user:131:r-x
group::r-x
mask::r-x
other::r-x

# file: nagios/nagios3.cfg
# owner: jturner
# group: jturner
user::rw-
user:131:r--
group::r--
mask::r--
other::r--
"""

class ACL
	def initialize(str)
		@str = str
		binding.pry
		@recs = @str.split("\n\n").collect { |filerec|

		}
	end

	def to_s
		@str
	end
end

ACL.new(s)
