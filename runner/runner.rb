require 'json'
require 'open3'

class StepFailed < RuntimeError
  def initialize(phase, location)
    super("on lines #{location} in phase #{phase}")
  end
end

all_steps = JSON.load(File.read(ARGV.first))

def report_error(e)
  puts
  puts red { "#{e.class}: #{e}" }
  puts
  $all_passed = false
end

def run_phase(all_steps, name)
  puts(bold { underline { name}})
  steps = all_steps[name]
  if steps.empty?
    puts yellow { '  - No steps in this phase'}
  else
    steps.each do |step|
      puts blue { "  + Running step #{step["line_span"]}" }

      shellcode = "set +e\n" + step["shell"]
      Open3.popen2e(step["shell"]) do |stdin, stdout_stderr, wait_exit_code_of_child|
        stdout_stderr.each do |line|
          puts((blue { "  | "}) + line)
        end

        if wait_exit_code_of_child.value != 0
          raise StepFailed.new(name, step["line_span"])
        end
      end
    end
  end
ensure
  puts
end

def bold
  "\033[1m" + yield + "\033[0m"
end

def underline
  "\033[4m" + yield + "\033[0m"
end

def red
  "\033[31m" + yield + "\033[0m"
end

def yellow
  "\033[33m" + yield + "\033[0m"
end

def blue
  "\033[34m" + yield + "\033[0m"
end

begin
  run_phase(all_steps, "pre-install")
rescue StepFailed => e
  report_error(e)
  exit 1
end
  
all_passed = true
begin
  run_phase(all_steps, "create-infrastructure")
  run_phase(all_steps, "run-tests")
rescue Exception => e
  report_error(e)
  puts "Skipping next steps, jump to cleaning up\n"
  all_passed = false
end

begin
  run_phase(all_steps, "destroy-infrastructure")
rescue Exception => e
  report_error(e)
  puts "    " + bold { red { "#" * 46 } }
  puts "    " + bold { red { "#   " } } + bold { red { underline { "Failed to clean up the infrastructure!" } } } + bold { red { "   #"}}
  puts "    " + bold { red { "#" * 46 } }
  exit 2
end

if all_passed
  exit 0
else
  exit 1
end
