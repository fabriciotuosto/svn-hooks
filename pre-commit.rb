#!/bin/env jruby 

require 'logger'

@exit_value = 0

# Creates and mantains the regular expression
# of the current project in an instance variable @preffix_regexp
def create_regex_for_preffix(preffix)
  @preffix_regexp = /#{preffix}-\d+/
end

# Initialize the basic configuration to start the commit validation
def init 
    $LOG = Logger.new(config.pre_commit_log_file,:pattern => config.log_pattern)
    repository = ARGV.shift
    transaction = ARGV.shift
    raise 'Bad Arguments' if !transaction or !repository
    @projects = create_projects # parse the projects configuration
    @commit = Commit.new(repository,transaction)
    @closed_status=config.closed_status

end

def hook_failed(message,show_log=false)
	$LOG.info("Message = #{message}")
	if show_log
		STDERR.puts message
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
  require File.dirname(__FILE__) +'/hooks_common.rb'
  init
  # If forced key configurated by repository is found on the message log
  # this will make it pass without checking the rest of the svn commit
  if feature_enable?('force_commit')  	
  	(exit(0);send_force_commit_mail("#{Time.now} #{@commit.author} has make a forced commit")) if @commit.message.match(/#{config.force}/)
  end

  # Finds the project that match
  project = @projects.detect { |p| @commit.message=~(create_regex_for_preffix(p.preffix))}
  # Obtains the issue keys from the log message
  result =  @commit.message.match(@preffix_regexp)
  
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
      
      unless @commit.author == issue_tracker.issue_assignee(issue) 
      	hook_failed("User #{@commit.author} is not authorize to commit in this issue",feature_enable?('validate_author'))
      end
  end # Unless issue
rescue Exception => e
	hook_failed(e.backtrace.join("\n"))
ensure
  issue_tracker.logout if issue_tracker
  exit(@exit_value)
end
