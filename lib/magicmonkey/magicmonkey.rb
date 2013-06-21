require 'optparse'
require 'pp'
require 'tempfile'
require 'cocaine'
require 'term/ansicolor'
require "#{$APP_PATH}/lib/magicmonkey/version"
require "#{$APP_PATH}/lib/magicmonkey/configuration"
include Term::ANSIColor

module Magicmonkey

  @o = {}

  COMMANDS = %w(configure deconfigure enable disable show vhost start stop restart)

  def self.main
    #Process::UID.change_privilege(Conf[:uid] || Process.uid)
    raise 'You cannot do this as root' if Process.uid == 0

    @o = Marshal.load(Marshal.dump(Conf[:default]))
    parser = OptionParser.new do |opts|
      opts.banner = 'Usage: magicmonkey <command> [<args>]'
      opts.separator ''
      opts.separator "Commands: #{COMMANDS.join(' ')}"
      opts.separator 'For more information about a specific command, please type'
      opts.separator "'magicmonkey <command> --help', e.g. 'magicmonkey configure --help'."
      opts.separator ''
      opts.separator 'Options:'
      opts.on_tail('-v', '--version', 'Print version') { puts Magicmonkey::VERSION; exit }
      opts.on_tail('-h', '--help', 'Show this help message') { puts opts; exit }
    end
    begin
      parser.order!
      command = (ARGV & COMMANDS).first
      raise 'Invalid command.' unless command
      ARGV.delete(command)
    rescue => e
      puts parser.help; exit
    end
    app = ARGV.first
    self.send(command, ARGV)
  end

  #####################
  # CONFIGURE COMMAND #
  #####################
  def self.configure(args)
    app = self.help('configure', 'Configure the application', args) do |opts|
      opts.on('-c', '--configuration CONFIG_FILE', 'Use this file as configuration') do |c|
        @o[:configuration] = c
      end
    end

    app_conf = Conf[app.to_sym]
    unless app_conf
      app_conf = @o.select{|k,v| [:app_server, :app_server_options, :ruby, :app_path, :bundle_exec].include?(k)}
      app_conf[:app_path].gsub!('$APP', app)
      app_conf[:port] = Conf.next_port
    end
    tmpfile = Tempfile.new("#{app}.yml")
    tmpfile.write(app_conf.to_yaml)
    tmpfile.close
    system("#{@o[:editor]} '#{tmpfile.path}'")
    conf = YAML.load_file(tmpfile.path)
    tmpfile.unlink

    self.check_port!(conf[:port]) if app_conf[:port] != conf[:port]
    self.check_ruby_version!(conf[:ruby])
    self.check_app_server!(conf[:app_server])

    Conf[app.to_sym] = conf
    Conf.save
  end

  #######################
  # DECONFIGURE COMMAND #
  #######################
  def self.deconfigure(args)
    app = help('deconfigure', 'The application will no longer be handled by magicmonkey.', args)
    app_conf = Conf[app.to_sym]
    unless app_conf
      rputs "Application '#{app}' does not configured."
      puts  "Use 'magicmonkey configure #{app}' to configure it."
      exit
    else
      Conf.delete(app)
      Conf.save
    end
  end

  ##################
  # ENABLE COMMAND #
  ##################
  def self.enable(args)
    applications = help2('enable', 'Enable the selected applications', args)
    applications.each do |app|
      Conf[app][:enabled] = true
    end
    Conf.save
  end

  ###################
  # DISABLE COMMAND #
  ###################
  def self.disable(args)
    applications = help2('disable', 'Disable the selected applications', args)
    applications.each do |app|
      Conf[app][:enabled] = false
    end
    Conf.save
  end

  ################
  # SHOW COMMAND #
  ################
  def self.show(args)
    applications = help2('show', 'Shows the configurations of selected applications', args) do |opts|
      opts.on('-e', '--enabled', 'Show enabled applications.') do |s|
        @o[:enabled] = s
      end
    end
    applications.select!{|k| Conf[k.to_sym][:enabled]} if @o[:enabled]
    applications.each do |app|
      puts app.upcase
      pp Conf[app]
      puts '-' * 80
    end
  end

  #################
  # START COMMAND #
  #################
  def self.start(args)
    self.run('start', args)
  end

  ################
  # STOP COMMAND #
  ################
  def self.stop(args)
    self.run('stop', args)
  end

  ###################
  # RESTART COMMAND #
  ###################
  def self.restart(args)
    self.run('restart', args)
  end

  private

  def self.run(action, args)
    applications = help2(action, "#{action.capitalize} the selected applications.", args)
    applications.select{|k| Conf[k.to_sym][:enabled]}.each do |app|
      app_conf = Conf[app.to_sym]
      unless app_conf
        rputs "Application '#{app}' does not configured."
        puts  "Use 'magicmonkey configure #{app}' to configure it."
        exit
      end
      check_ruby_version!(app_conf[:ruby])
      server = check_app_server!(app_conf[:app_server])
      command = self.build_command(app) do
        if action == 'restart'
          [server.stop(app_conf), 'sleep 3', server.start(app_conf)]
        else
          server.send(action, app_conf)
        end
      end
      begin
        print "Calling #{bold}#{action}#{reset} for '#{app}' application..."
        Dir.chdir(app_conf[:app_path]) do
          Cocaine::CommandLine.new(command).run
        end
        puts " #{green}#{bold}done#{reset}."
      rescue Cocaine::ExitStatusError => e
        rputs "Failed to #{action} application '#{app}'"
      end
    end
  end

  def self.build_command(app)
    app_conf = Conf[app.to_sym]
    lines = []
    lines << "source '#{Dir.home}/.rvm/scripts/rvm'"
    lines << "rvm use #{app_conf[:ruby]}"
    lines += yield if block_given?
    command = "bash -c \"#{lines.join(' && ')}\""
    if app_conf[:bundle_exec]
      command.gsub!(" && #{app_conf[:app_server]} ", " && bundle exec #{app_conf[:app_server]} ")
    end
    return command
  end

  def self.check_port!(port)
    if Conf.ports.include?(port)
      rputs 'Invalid port number. This port is used by another application or is invalid.'
      exit
    end
  end

  def self.check_ruby_version!(ruby)
    rubies = ['default', 'system']
    begin
      res = Cocaine::CommandLine.new('rvm list').run
    rescue Cocaine::CommandNotFoundError
      rputs 'RVM (Ruby Verison Manager) is not installed in your system. Please install RVM to use Magicmonkey.'
      exit
    end
    res.each_line do |line|
      match = line.match(/\s((?:ruby|jruby|rbx|ree|macruby|maglev|ironruby)\S+?)\s/)
      rubies << match[1] if match
    end
    unless rubies.include?(ruby)
      rputs "Ruby version specified ('#{ruby}') is not installed in your system."
      rputs "Valid Ruby versions are: #{rubies.join(', ')}."
      exit
    end
  end

  def self.check_app_server!(app_server)
    unless app_server
      rputs 'You must specify the application server.'
      exit
    end
    begin
      Cocaine::CommandLine.new("#{app_server} -v").run
    rescue Cocaine::CommandNotFoundError
      rputs "The application server '#{app_server}' is not installed in your system."
      rputs 'Please use a valid and installed application server.'
      exit
    rescue
    end
    begin
      require "#{$APP_PATH}/lib/magicmonkey/app_servers/#{app_server}"
      m = ''
      i = 0
      app_server.each_char do |c|
        app_server[i-1] == '_' ? m << c.upcase : m << c if c != '_'
        i+=1
      end
      m[0] = m[0].upcase
      const_get(m)
    rescue LoadError, NameError
      rputs "No module '#{m}' found in #{$APP_PATH}/lib/magicmonkey/app_servers/#{app_server}.rb"
      rputs "You must create a module called '#{app_server.capitalize}' to tell how to start, stop and restart the server."
      exit
    end
  end

  def self.help(command, desc, args)
    parser = OptionParser.new do |opts|
      opts.banner = "Usage: magicmonkey #{command} APP_NAME"
      opts.separator ''
      if desc
        opts.separator desc
        opts.separator ''
      end
      opts.separator 'Options:'
      yield(opts) if block_given?
      opts.on_tail('-h', '--help', 'Show this help message') { puts opts; exit }
    end
    begin
      args = parser.parse!(args)
      raise 'Missing application name.' if args.size != 1
    rescue => e
      puts parser.help; exit
    end
    return args.first
  end

  def self.help2(command, desc, args)
    parser = OptionParser.new do |opts|
      opts.banner = "Usage: magicmonkey #{command} [APP_NAME1 APP_NAME2 ...]"
      opts.separator ''
      if desc
        opts.separator desc
        opts.separator "If no application name passed, #{command} all applications."
        opts.separator ''
      end
      opts.separator ''
      opts.separator 'Options:'
      yield(opts) if block_given?
      opts.on_tail('-h', '--help', 'Show this help message') { puts opts; exit }
    end
    begin
      args = parser.parse!(args)
    rescue => e
      puts parser.help; exit
    end
    applications = Conf.applications
    applications &= args.map(&:to_sym) unless args.empty?
    return applications
  end

  def self.rputs(message)
    puts "#{red}#{message}#{reset}"
  end

end
