module DeployDoc
  module CLI
    def self.run!(arguments)
      configuration = parse_arguments(arguments)

      test_plan = TestPlan.from_file(configuration.markdown_file)
      
      case configuration.action
        when :run then self.do_run(test_plan, configuration)
        when :output_shell_script then self.output_shell_script(test_plan, configuration)
        when :just_docker_env then self.just_docker_env(test_plan, configuration)
      end
    rescue DeployDoc::Error => e
      puts "Runtime error: #{e.message}"
      exit 1
    end

    def self.parse_arguments(arguments)
      configuration = Config.defaults

      opt_parser = OptionParser.new do |opts|
        opts.banner = "Usage: deploy_doc <markdown_file> [options]"

        opts.on("-h", "--help", "Print help") do
          puts opts
          exit
        end

        opts.on("-r", "--run-test", "Run tests") do
          configuration.action = :run
        end
       
        opts.on("-s", "--output-shell-script", "Just generate a shell script containing all the steps") do
          configuration.action = :output_shell_script
        end

        opts.on("-c", "--shell-in-container", "Start a (temporary) docker container with the same environment as the tests will run in") do
          configuration.action = :just_docker_env
        end

        opts.on("-i", "--docker-image", "Use this docker image instead of the default '#{configuration.docker_image}'") do |image|
          configuration.docker_image = image
        end

        opts.on("-d", "--data-dir", "Set the data directory, instead of the default '#{configuration.data_dir}'")do |data_dir|
          configuration.data_dir = data_dir
        end
      end
      opt_parser.parse!(arguments)
      configuration.markdown_file = arguments.shift

      if configuration.markdown_file.nil?
        raise DeployDoc::Error.new("No markdown file provided!")
      end
      
      if configuration.action.nil?
        raise DeployDoc::Error.new("No action given. Either --run-tests, --output-shell-script or --shell-in-container must be specified")
      end

      configuration
    end

    def self.do_run(test_plan, configuration)
      test_instructions_file = Tempfile.new("deploydoc")
      test_instructions_file.write test_plan.to_json
      test_instructions_file.close
      runner_path = File.expand_path("../../../runner/runner.rb", __FILE__)
      extra_opts = [
        "-v#{test_instructions_file.path}:/deploy_doc/steps.json",
        "-v#{runner_path}:/deploy_doc/runner"
      ]
      system Docker.cmd(configuration, check_and_find_envs(test_plan), "ruby /deploy_doc/runner /deploy_doc/steps.json", extra_opts)
      test_instructions_file.close
      test_instructions_file.unlink
      exit $?.exitstatus
    end

    def self.output_shell_script(test_plan, configuration)
      puts test_plan.to_shell_script
    end

    def self.just_docker_env(test_plan, configuration)
      Kernel.exec Docker.cmd(configuration, check_and_find_envs(test_plan), "sh", ["-ti"])
    end

    def self.check_and_find_envs(test_plan)
      test_plan.required_env_vars.map do |name|
        val = ENV[name]
        if val.nil?
          $stderr.puts "Required environmental variable #{name} is not set"
          exit 1
        else
          "-e#{name}=#{val}"
        end
      end.join(" ")
    end
  end
end
