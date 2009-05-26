#!/bin/env jruby 

require 'rubygems'
require 'yaml'
require 'cgi'
require 'actionmailer'
require 'ostruct'
require 'erb'

# Exception use to validate
class ValidationException < Exception
	
end
# Arreglo de error en wsdl
# SOAP::WSDLDriverFactory.
# server.options["protocol.http.ssl_config.verify_mode"] = nil 


#
# configuration
#
class Configuration
  include Singleton 
  def initialize
    file_name = File.dirname(__FILE__) + '/configuration.yaml'
    raise "Configuration file not found in the path #{file_name}" unless File.exist?(file_name)
    @configuration_container = OpenStruct.new(YAML.load(File.open(file_name)))
  end
  
  def value(key)
    @configuration_container.send key
  end
  
  def method_missing(sym, *args, &block)
    @configuration_container.send sym, *args, &block
  end  
end

def config
  Configuration.instance
end



# Parse the project to easyness the acess to the metadata of the project
class Project
  attr_reader :name , :folder , :preffix  
  def initialize(argument)
    arg = OpenStruct.new(argument)
    @name    = arg.name
    @folder  = arg.folder
    @preffix = arg.jira_prefix
  end  
end


class FileDiff
  attr_accessor  :operation, :file_name , :rev1 , :rev2 , :html_text
  def initialize
    @operation = nil
    @file_name = nil
    @rev1      = nil
    @rev2      = nil
    @html_text = ''
  end
end

# Holds the commit information to validate the commit
class Commit
  attr_reader :message, :author, :dir_changed, :date,:patch 
  def initialize(repository,transaction)
    svnlook = config.svnlook
    # Subversion suggests that svnlook might create files.
    Dir.chdir("/tmp")
    @message      = `#{svnlook} log          #{repository} -t #{transaction}`.chomp
    @author       = `#{svnlook} author       #{repository} -t #{transaction}`.chomp
    @dir_changed  = `#{svnlook} dirs-changed #{repository} -t #{transaction}`
    @date         = `#{svnlook} date         #{repository} -t #{transaction}`.chomp
    @patch        = `#{svnlook} diff         #{repository} -t #{transaction}`
    @message      ||= ''
  end
end

# Information retrieved when the commit has already happend
class Revision
    attr_reader :message,:author,:date,:patch,:subject,:added,:modified,:removed,:props_modified,:number,:repository
    def initialize(repository,transaction)
      svnlook = config.svnlook
      # Subversion suggests that svnlook might create files.
      Dir.chdir("/tmp")
      info            = `#{svnlook} info #{repository} -r #{transaction}`.split("\n")
      @number         = transaction
      @author         = CGI.escapeHTML(info.shift)
      @date           = info.shift
      @size           = info.shift
      @subject        = CGI.escapeHTML(info[0])
      @message        = CGI.escapeHTML(info.join("\n"))
      @patch          = `#{svnlook} diff #{repository} -r #{transaction}`
      @repository     = repository
      @added          = []
      @modified       = []
      @removed        = []
      @props_modified = []

      `#{svnlook} changed #{repository} -r #{transaction}`.split("\n").each do |line|
	        op = line[0,1]
	        props = line[1,1]
	        file = line[4..-1]
	
	        # escape the filename
	        file = CGI.escapeHTML(file)
	
	        case op
	          when 'A' then @added.push(file)
	          when 'U' then @modified.push(file)
	          when 'D' then @removed.push(file)
	        end
	
	        @props_modified.push(file) if props == 'U'
      end
    end

    # Support templating of member data.
    def get_binding
      binding
    end

  end

#
# TODO
#
class Emailer < ActionMailer::Base

  # Creates the post-commit mail
  def svn_mail(mails,subject,revision,body,diff)
   subject         "[svn] #{revision} - #{config.root} #{subject}"
   from            'svnadmin@ithol'
   recipients      mails
   content_type    'text/html'
   body            body
   attachment      :content_type => 'text/plain', :body => diff, :filename => "diff-r#{revision}.patch"
 end
 
 # Creates the force_commit mail
 def forced_commit(mails,body)
   subject         'Forced commit realized'
   from            'svnadmin@ithol'
   recipients      mails
   content_type    'text/html'
   body            body
 end 
end

# Class that encapsulates the behavoir needed by an issue tracker
# this could be extended or modified in order to work with another
# issue tracker, by now it only supports Jira
class JiraTracker

  def initialize
    require 'jira4r/jira4r'
    # Connect to jira
    jira_config = OpenStruct.new(config.jira_configuration)
    @tracker = Jira4R::JiraTool.new(jira_config.wsdl_version, jira_config.url)
    @tracker.login(jira_config.username, jira_config.password)
  end


  # Return the issue from, this is only accesible if the configured user has
  # privileges on the project at least to only view this current project
  def issue(issue_key)
    @tracker.getIssue(issue_key)
  end  

  # Add a comment to the issue , describing who and when make the commit
  def add_comment_to_issue(issue, author)
    comment= RemoteComment.new("#{Time.now} , #{author} make a commit on this issue")
    @tracker.addComment(issue.key,comment)
  end

  # Find the jira project by the project key
  # ( having some trouble finding the project by name and validate 
  # how the to determine if the issue belongs to the project or not)
  def project(key)
    @tracker.getProjects.detect { |pro| pro.key == key }
  end

  def project_name(key)
    pro = project(key)
    pro.name if pro
  end

  # Obtains the asignee of the given issue
  def issue_assignee(issue)
    issue.assignee
  end
  
  # Obtaints the status of the issue
  def issue_status(issue)
    issue.status
  end
  
  # Close jira session
  def logout()
    @tracker.logout
  end
end

#
# action mailer
#
delivery_method = config.delivery_method
ActionMailer::Base.delivery_method = delivery_method
ActionMailer::Base.send(delivery_method.to_s+'_settings=',config.mailer)

# TODO
def post_commit_html(revision)
  rhtml = ERB.new(erb)
  rhtml.result(revision.get_binding)
end

# Helper method to encapsulate the logic of sending the mail
def send_post_commit_mail(revision)
  body = post_commit_html(revision)
  mail = Emailer.create_svn_mail(config.mails,revision.subject,revision.number,body,revision.patch)
  Emailer.deliver(mail)
end

# Helper method to encapsulate the logic of sending the mail
def send_force_commit_mail(body)
  mail  = Emailer.create_foced_commit(config.force_commit_mails,body)
  Emailer.deliver(mail)
end

# Method that parse the configuration and creates
# the projects that have been configure by repository
def create_projects
  projects = []
  config.projects.each do |project|
    projects << Project.new(project)
  end
  projects
end

# True if the feature asked in the configuration is enable
def feature_enable?(feature)
  @features ||= config.features_enable
  @features[feature] == true
end

def stylesheet
  load_file('post-commit.css')
end
  
def javascripts
  load_file('post-commit.js')
end
  
def erb
  load_file('post-commit.erb')
end

def transform_line(line)
  CGI.escapeHTML(line).gsub(' ', '&nbsp;')
end

def parse_file_diff(diff)
  files_diff = []
  file_diff = nil
  diff.each_line do |line|

    if (line =~ /^=/)
      next
    end

    if (line =~ /^(Modified|Added|Deleted|Copied): (.*)/)
      file_diff = FileDiff.new
      files_diff << file_diff
      file_diff.operation = "#$1"
      file_diff.file_name = "#$2"
      next
    end

    if (line =~/^\(Binary files differ\)/ )
      file_diff.html_text << "<span class='cx'>#{transform_line(line)}</span>\n"
      file_diff.html_text << "</div>"
      next
    end

    if (line =~ /^---.*rev (\d+)\)$/)
      file_diff.rev1 = "#$1"
      next
    end

    if (line =~ /^\+\+\+.*rev (\d+)\)$/)
      file_diff.rev2 = "#$1"
      next
    end

    if (line =~ /^\@\@/)
      file_diff.html_text << "<span class='lines'>#{transform_line(line)}</span>\n"
      next
    end

    if (line =~ /^([-+])/)
      style = "#$1" == '+' ? 'ins' : 'del'
      file_diff.html_text << "<span class='#{style}'>#{transform_line(line[2..-1])}</span>\n"
      next
    end
    
    file_diff.html_text << "<span class='cx'>#{CGI.escapeHTML(line)}</span>\n"
    
  end

  files_diff
end


private
def load_file(file_name)
  file_str = nil
  path = File.join(config.html_files_path,file_name)
  File.open(path, 'r') do |file|
    file_str = file.read
  end
  file_str
end
