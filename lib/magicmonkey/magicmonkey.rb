require 'optparse'
require 'pp'
require 'cocaine'
require 'term/ansicolor'
require "#{$APP_PATH}/lib/magicmonkey/version"
require "#{$APP_PATH}/lib/magicmonkey/configuration"
include Term::ANSIColor

module MagicMonkey

  COMMANDS = [:start, :stop, :restart, :add, :remove, :show]

  def self.main
    #Process::UID.change_privilege(Conf[:uid] || Process.uid)
    raise 'You cannot do this as root' if Process.uid == 0

    options = Marshal.load(Marshal.dump(Conf[:default]))
    parser = OptionParser.new do |opts|
      opts.banner = 'Usage: magicmonkey <command> [<args>]'
      opts.separator ''
      opts.separator "Commands: #{COMMANDS.join(' ')}"
      opts.separator 'For more information about a specific command, please type'
      opts.separator "'magicmonkey <command> --help', e.g. 'magicmonkey add --help'"
      opts.separator ''
      opts.separator 'Options:'
      opts.on_tail('-v', '--version', 'Print version') { puts Magicmonkey::VERSION; exit }
      opts.on_tail('-h', '--help', 'Show this help message') { puts opts; exit }
    end
    begin
      parser.order!
      command = ARGV[0]
      ARGV.shift
      raise 'Invalid command.' unless COMMANDS.include?(command.to_sym)
    rescue => e
      rputs e
      puts parser.help; exit
    end

    case command
    when 'add'
      self.add(ARGV, options)
    when 'start'
      start_stop_restart(:start, ARGV)
    when 'stop'
      start_stop_restart(:stop, ARGV)
    when 'restart'
      start_stop_restart(:restart, ARGV)
    when 'remove'
      remove(ARGV)
    when 'show'
      show(ARGV)
    end
  end


  def self.add(args, o = {})
    tmp = args.join('$$').split(/\$\$--\$\$/)
    args = tmp[0].split('$$')
    o[:app_server_options] = tmp[1].split('$$').join(' ') if tmp[1]

    parser = OptionParser.new do |opts|
      opts.banner = 'Usage: magicmonkey add APP_NAME [options] -- application_server_options'
      opts.separator ''
      opts.separator 'Options:'
      opts.on('-s', '--app-server APP_SERVER', "Use the given application server (e.g. passenger, thin, unicorn, default: #{o[:app_server]}).") do |s|
        o[:app_server] = s
      end
      opts.on('-p', '--port NUMBER', Integer, "Use the given port number (default: #{Conf.next_port}).") do |p|
        o[:port] = p
      end
      opts.on('-r', '--ruby RUBY_VERSION', "Use the given Ruby version (default: #{o[:ruby]}).") do |r|
        o[:ruby] = r
      end
      opts.on('--app-path APP_PATH', "Use the given application path (default #{o[:app_path]}).") do |path|
        o[:app_path] = path
      end
      opts.on('--server-name SERVER_NAME', "Use the given server name (default: #{o[:server_name]}).") do |name|
        o[:server_name] = name
      end
      opts.on('--vhost-template TEMPLATE', "Use the given virtual host template file.") do |template|
        o[:vhost_template] = template
      end
      opts.on('--vhost-path VHOST_PATH', "Use the given virtual host path (default: '#{o[:vhost_path]}').") do |path|
        o[:vhost_path] = path
      end
      opts.on('-f', '--[no-]overwrite-files', "Replace exist files (default: #{o[:overwrite_files]}).") do |f|
        o[:overwrite_files] = f
      end
      opts.on('--[no-]create-vhost', "Create virtual host file from template (default: #{o[:create_vhost]}).") do |c|
        o[:create_vhost] = c
      end
      opts.on('--[no-]enable-site', "Enable Apache virtual host (default: #{o[:enable_site]}).") do |e|
        o[:enable_site] = e
      end
      opts.on('--[no-]reload-apache', "Reload apache to load virtual host (default: #{o[:reload_apache]}).") do |r|
        o[:reload_apache] = r
      end
      opts.on_tail('-v', '--version', 'Print version') { puts Magicmonkey::VERSION; exit }
      opts.on_tail('-h', '--help', 'Show this help message') { puts opts; exit }
    end
    begin
      args = parser.parse!(args)
      raise 'Missing application name.' if args.size != 1
    rescue => e
      rputs e
      puts parser.help; exit
    end

    # Ok goo
    app_name = args.first
    if Conf.applications.include?(app_name.to_sym)
      rputs "Application '#{app_name}' already added. Try to use another name."
      exit
    end
    o[:app_path].gsub!('$APP_NAME', app_name) if o[:app_path] == Conf[:default][:app_path]
    o[:server_name].gsub!('$APP_NAME', app_name) if o[:server_name] == Conf[:default][:server_name]
    o[:port] ||= Conf.next_port
    if Conf.ports.include?(o[:port])
      rputs 'Invalid port number. This port is used by another application or is invalid.'
      exit
    end
    self.check_ruby_version!(o[:ruby])
    self.check_app_server!(o[:app_server])
    o[:vhost_template].gsub!('$APP_NAME', app_name)
    o[:vhost_template].gsub!('$SERVER_NAME', o[:server_name])
    o[:vhost_template].gsub!('$PORT', o[:port].to_s)

    puts "Configuration for application '#{app_name}' is:"
    pp o
    print 'Add this application? [Y/n]'
    input = STDIN.gets.chop
    if input.upcase == 'Y' || input == ''
      if o[:create_vhost]
        vh_file = "#{o[:vhost_path]}/#{app_name}"
        if (!File.exist?(vh_file) || o[:overwrite_files])
          begin
            Cocaine::CommandLine.new("sudo bash -c \"echo '#{o[:vhost_template]}' > #{vh_file}\"").run
          rescue Cocaine::ExitStatusError => e
            rputs 'Failed to write virtual host file.'
          end
        else
          puts "Virtual host file '#{vh_file}' already exist. Use option '-f' to replace it. Skip creation."
        end
      end
      if o[:enable_site]
        begin
          Cocaine::CommandLine.new("sudo a2ensite '#{app_name}'").run
        rescue Cocaine::ExitStatusError => e
          rputs 'Failed to enable the site.'
        end
      end
      if o[:enable_site] && o[:reload_apache]
        begin
          Cocaine::CommandLine.new('sudo /etc/init.d/apache2 reload').run
        rescue Cocaine::ExitStatusError => e
          rputs 'Failed to reload Apache.'
        end
      end
      Conf[app_name] = o.select{|k,v| [:ruby, :port, :app_server, :app_server_options, :app_path, :vhost_path].include?(k)}
      Conf.save

      puts "#{green}Application '#{app_name}' added.#{reset}"
      puts "use 'magicmonkey start #{app_name}' to start the application."
    end
  end

  def self.remove(args)
    o = {:remove_vhost => false}
    parser = OptionParser.new do |opts|
      opts.banner = 'Usage: magicmonkey remove APP_NAME'
      opts.separator ''
      opts.separator 'Options:'
      opts.on('--[no-]remove-vhost', "Remove the virtual host file if exist (default: #{o[:remove_vhost]}).") do |r|
        o[:remove_vhost] = r
      end
      opts.on_tail('-v', '--version', 'Print version') { puts Magicmonkey::VERSION; exit }
      opts.on_tail('-h', '--help', 'Show this help message') { puts opts; exit }
    end
    begin
      args = parser.parse!(args)
      raise 'Missing application name.' if args.size != 1
    rescue => e
      rputs e
      puts parser.help; exit
    end
    app_name = args.first
    if Conf[app_name]
      self.start_stop_restart(:stop, [app_name])
      begin
        Cocaine::CommandLine.new("sudo a2dissite '#{app_name}'").run
      rescue Cocaine::ExitStatusError => e
        rputs 'Failed to disable site.'
      end
      vh_file = "#{Conf[app_name][:vhost_path]}/#{app_name}"
      if o[:remove_vhost] && File.exist?(vh_file)
        begin
          Cocaine::CommandLine.new("sudo rm -f '#{vh_file}'").run
        rescue Cocaine::ExitStatusError => e
          rputs 'Failed to remove virtual host file.'
        end
      end
      Conf.delete(app_name)
      Conf.save
      puts "Application '#{app_name}' removed."
    else
      rputs "Application '#{app_name}' does not exist."
    end
  end

  def self.start_stop_restart(ssr, args)
    parser = OptionParser.new do |opts|
      opts.banner = "Usage: magicmonkey #{ssr} [APP_NAME1 ... APP_NAME2 ...]"
      opts.separator "If no application name passed, #{ssr} all applications."
      opts.separator ''
      opts.separator 'Options:'
      opts.on_tail('-v', '--version', 'Print version') { puts Magicmonkey::VERSION; exit }
      opts.on_tail('-h', '--help', 'Show this help message') { puts opts; exit }
    end
    begin
      args = parser.parse!(args)
    rescue => e
      rputs e
      puts parser.help; exit
    end
    applications = args
    applications = Conf.applications if applications.empty?
    applications.each do |app_name|
      o = Conf[app_name.to_sym]
      if o
        check_ruby_version!(o[:ruby])
        server = check_app_server!(o[:app_server])
        print "Calling #{bold}#{ssr}#{reset} for '#{app_name}' application..."
        STDOUT.flush
        begin
          output = self.run(o){server.send(ssr, o)}
          puts " #{green}#{bold}done#{reset}."
        rescue Cocaine::ExitStatusError => e
          puts ''
          rputs "Failed to #{ssr} application '#{app_name}'"
        end
      else
        rputs "Application '#{app_name}' is not added."
        rputs "use 'magicmonkey add #{app_name}' to add this application."
      end
    end
  end

  def self.show(args)
    parser = OptionParser.new do |opts|
      opts.banner = "Usage: magicmonkey show [APP_NAME1 ... APP_NAME2 ...]"
      opts.separator 'If no application name passed, show the configuration of all applications.'
      opts.separator ''
      opts.separator 'Options:'
      opts.on_tail('-v', '--version', 'Print version') { puts Magicmonkey::VERSION; exit }
      opts.on_tail('-h', '--help', 'Show this help message') { puts opts; exit }
    end
    begin
      args = parser.parse!(args)
    rescue => e
      rputs e
      puts parser.help; exit
    end
    applications = args
    applications = Conf.applications if applications.empty?
    applications.each do |app_name|
      puts app_name.upcase
      pp Conf[app_name]
      puts '-'*80
    end
  end

  private

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
      rputs 'Please use --app-server option. e.g. magicmonkey add APP_NAME --app-server=passenger'
      exit
    end
    begin
      Cocaine::CommandLine.new(app_server).run
    rescue Cocaine::CommandNotFoundError
      rputs "The application server '#{app_server}' is not installed in your system."
      rputs 'Please use a valid and installed application server.'
      exit
    rescue
    end
    begin
      require "#{$APP_PATH}/lib/magicmonkey/app_servers/#{app_server}"
      const_get(app_server.capitalize)
    rescue LoadError, NameError
      rputs "No module '#{app_server.capitalize}' found in #{$APP_PATH}/lib/magicmonkey/app_servers/#{app_server}.rb"
      rputs "You must create a module called '#{app_server.capitalize}' to tell how to start, stop and restart the server."
      exit
    end
  end

  def self.run(options)
    lines = []
    lines << "source #{Dir.home}/.rvm/scripts/rvm"
    lines << "rvm use #{options[:ruby]}"
    lines << "cd #{options[:app_path]}"
    res = yield
    if res.class == Array
      lines += res
    elsif res.class == String
      lines << res
    end
    line = Cocaine::CommandLine.new("bash -c '#{lines.join(' && ')}'")
    line.run
  end

  def self.rputs(message)
    puts "#{red}#{message}#{reset}"
  end

end
