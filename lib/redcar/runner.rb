

module Redcar
  
  # Cribbed from ruby-processing. Many thanks!
  class Runner
    
    # Trade in this Ruby instance for a JRuby instance, loading in a 
    # starter script and passing it some arguments.
    # If --jruby is passed, use the installed version of jruby, instead of 
    # our vendored jarred one (useful for gems).
    def spin_up
      bin = "#{File.dirname(__FILE__)}/../../bin/redcar"
      jruby_complete = Dir[File.dirname(__FILE__) + "/../jruby-complete-1.4.0.jar"].first
      args = []
      if false
        command = "jruby #{java_args} \"#{bin}\" #{ARGV.join(' ')}"
      else
        command = "java #{java_args} -cp \"#{jruby_complete}\" org.jruby.Main \"#{bin}\" #{ARGV.join(' ')}"
      end
      exec(command)
    end
    
    def java_args
      if Config::CONFIG["host_os"] =~ /darwin/
        "-XstartOnFirstThread"
      else
        ""
      end
    end
  end
end