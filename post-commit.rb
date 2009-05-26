#!/bin/env jruby 

require 'rubygems'
require 'cgi'
require 'erb'

#
# convert a list of files to HTML
#
def files_to_html(title, list , rev , type )
  return "" if list.length == 0
  result = ' '
  result << "<h3>#{title}</h3>\n"
  result << "<div class='files'>\n"
  list.each do |file|
    result << ' '   
    result << "<div class='file'>\n"
    result << "<a href=#{create_viewvc_link(CGI.escapeHTML(file),rev,type)}>#{CGI.escapeHTML(file)}</a><br />\n"
    result << "</div>\n"
  end
  result << "</div>\n"
  result
end


def display_prop_changes(list)
  return "" if list.length == 0
  result = ' '
  list.each do |prop_file|
	  result << "<h4>Property changes: #{CGI.escapeHTML(prop_file)}</h4>"
  end
  result        	
end

def display_files_diff(patch)
  output = ''
  parse_file_diff(patch).each { |file|
    output << "<div class='difffile'>"
    output << "<h4>#{file.operation}: #{file.file_name} (#{file.rev1} => #{file.rev2})</h4>\n"
    output << file.html_text
    output << "</div>"
  }
  output
end

#
# create link viewvc
#
def create_viewvc_link(path,rev,type)
  previous_revision = rev.to_i - 1
  ip  =  config.viewvc_ip
  root = config.root
  case type
   when 'A' then return "http://#{ip}/viewvc/#{path}?root=#{root}&pathrev=#{rev}"
   when 'U' then return "http://#{ip}/viewvc/#{path}?root=#{root}&pathrev=#{rev}&view=diff&r1=#{rev}&r2=#{previous_revision}&diff_format=h"
   when 'D' then return "http://#{ip}/viewvc/#{path}?root=#{root}&pathrev=#{previous_revision}"
  end
end

begin
  require File.dirname(__FILE__) +'/hooks_common'

  # process ARGV
  @repository = ARGV.shift
  @revision   = ARGV.shift
  raise "Bad arguments" unless @repository and @revision

  revision_info = Revision.new(@repository,@revision)
  send_post_commit_mail(revision_info)

  exit(0)

rescue

  puts "Error #{$!}"
  raise
  
end
