#!/bin/env jruby 

require 'hooks_common'
require 'erb'
require 'logger'
=begin
def create_projects
  @projects = []
  config.value('projects').each { |project| 
    @projects << Project.new(project)
  }
end

def create_regex_for_preffix(preffix)
  @preffix_regexp = /^#{preffix}-\d*/
end




svnlog_valido = 'PTM-25 error bla bla PTM-30'
svnlog_forced = 'PTM-25 error forced! bla bla '

$LOG.info 'uno'; $LOG.info 'dos'\
  if true

$LOG.info config.delivery_method

$LOG.info config.value('delivery_method')

$LOG.info feature_enable?('validate_multiple_issues')

create_projects

project = @projects.detect { |p| svnlog_valido =~ create_regex_for_preffix(p.preffix) }

create_regex_for_preffix(project.preffix)

$LOG.info result =  @preffix_regexp.match(svnlog_valido)

$LOG.info result =  @preffix_regexp.match('')

$LOG.info config.force

$LOG.info svnlog_valido.match(config.force)

$LOG.info result =  @preffix_regexp.match(svnlog_valido)

$LOG.info result.to_a

issue_tracker = eval("#{config.tracker.capitalize}Tracker.new")
issue = issue_tracker.issue('SDM-21')

$LOG.info issue_tracker.project_name('SDM')

$LOG.info "Usuario =#{issue.assignee}"


$LOG.info issue_tracker.logout
#
#def load_file(file_name)
#  file_str = nil
#  File.open(file_name, 'r') do |file|
#    file_str = file.read
#  end
#  file_str
#end
#
#
#
#diff = load_file('doc/diff.txt')
#
#parse_diff(diff).each { |file|
#  $LOG.info file.file_name
#  $LOG.info file.operation
#  $LOG.info file.rev1
#  $LOG.info file.rev2
#  $LOG.info file.html_text
#}
#
#
#$LOG.info "#{config.tracker.capitalize}Tracker.new"
#
#@tracker = eval("#{config.tracker.capitalize}Tracker.new")
#
#$LOG.info @tracker
#

#$LOG.info @tracker.logout
=end





@exit_value = 0

# Creates and mantains the regular expression
# of the current project in an instance variable @preffix_regexp
def create_regex_for_preffix(preffix)
  @preffix_regexp = /#{preffix}-\d+/
end

# Initialize the basic configuration to start the commit validation
def init 
	$LOG = Logger.new($STDOUT,:pattern => config.log_pattern)
#    repository = ARGV.shift
#    transaction = ARGV.shift
#    raise 'Bad Arguments' if !transaction or !repository
    @projects = create_projects # parse the projects configuration
#    @commit = Commit.new(repository,transaction)
    @closed_status=config.closed_status

end

def hook_failed(message,show_log=false)
	$LOG.info("Message = #{message}")
	if show_log
		STDERR <<  message
		@exit_value = 1
	end
end

def log_issue(issue)
	$LOG.info("------------ Loggin issue ---------------")
	if issue
		$LOG.info("Issue =#{issue}")
		$LOG.info("Project =#{issue.project}")
		$LOG.info("Status =#{issue.status}")
		$LOG.info("Assignee =#{issue.assignee}")
	end
	$LOG.info("------------ Loggin issue ---------------")
end	

begin
	
  author='ftuost'
  message='SDM-21'
  
  require File.dirname(__FILE__) +'/hooks_common.rb'
  init
  # If forced key configurated by repository is found on the message log
  # this will make it pass without checking the rest of the svn commit
  if feature_enable?('force_commit')  	
  	(exit(0);send_force_commit_mail("#{Time.now} #{author} has make a forced commit")) if message.match(/#{config.force}/)
  end

  # Finds the project that match
  project = @projects.detect { |p| message=~(create_regex_for_preffix(p.preffix))}
  # Obtains the issue keys from the log message
  result =  message.match(@preffix_regexp)
  
  unless result
  	hook_failed("No jira issue key in the log message",feature_enable?('validate_issue_exist'))
  end
  
  issue_tracker = eval("#{config.tracker.capitalize}Tracker.new")
  issue = issue_tracker.issue(result)

  log_issue(issue)
  
  # Validates the existance of the issue
  unless issue
  	hook_failed("#{result} doesn't exist as a issue on Jira",feature_enable?('validate_jira_issue'))
  else
      # Validates that the issue belongs to the project is beeing commited
      unless project.name == issue.project || issue.project == issue_tracker.project_name(project.name)
      	hook_failed("#{result} Is not a valid jira issue key for the project #{project.name}",feature_enable?('validate_issue_project'))
      end
      
      # Validates that the issue is not
      if @closed_status.include?(issue_tracker.issue_status(issue))
      	hook_failed("#{result} is closed and no commit can be performed",feature_enable?('validate_issue_status'))
      end
      
      unless author == issue_tracker.issue_assignee(issue) 
      	hook_failed("User #{author} is not authorize to commit in this issue",feature_enable?('validate_author'))
      end
  end # Unless issue
  $LOG.info{"Finished Succesfully (?)"}
rescue Exception => e
	hook_failed(e.backtrace.join("\n"))
ensure
  issue_tracker.logout if issue_tracker
  $LOG.info{"Exiting with code = #{@exit_value}"}
  exit(@exit_value)
end
