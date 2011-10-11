require 'optparse'
require 'pp'
require 'etc'
require "#{$APP_PATH}/lib/magicmonkey/version"
require "#{$APP_PATH}/lib/magicmonkey/configuration"

module MagicMonkey
  COMMANDS = [:start, :stop, :restart, :add, :remove, :show]

  def self.main(argv)
    raise 'You cannot do this as root' if Process.uid == 0
    Process::UID.change_privilege(Conf[:uid] || Process.uid)
    command = argv[0]
    if command == '-v' || command == '--version'
      puts Magicmonkey::VERSION
      exit
    elsif command.nil? || command == '-h' || command == '--help' || !COMMANDS.include?(command.to_sym)
      main_help
      exit
    else
      send(command, argv[1..-1])
    end
  end

  def self.main_help
    puts 'Description here'
    puts
    puts 'Available commands:'
    puts
    COMMANDS.each do |c|
      puts "  magicmonkey #{c}\t\tdesc"
    end
    puts
    puts "Special options:"
    puts
    puts "  magicmonkey --help\t\tDisplay this help message."
    puts "  magicmonkey --version\t\tDisplay version number."
    puts
    puts "For more information about a specific command, please type"
    puts "'magicmonkey <COMMAND> --help', e.g. 'magicmonkey add --help'."
  end

  def self.show(argv)
    applications = argv
    applications = Conf.applications.keys if argv.empty?
    applications.each do |app_name|
      if Conf[app_name]
        puts app_name
        puts '-'*app_name.to_s.size
        pp Conf[app_name]
        puts
      else
        puts "Application '#{app_name}' not found."
      end
    end
  end

  def self.start(argv)
    v, help = common_options(argv)
    if help
      puts 'Start a web application added with ADD command. If no params are given start all web applications.'
      exit
    end
    applications = argv
    applications = Conf.applications.keys if argv.empty?
    applications.each do |app_name|
      if Conf[app_name]
        commands = []
        if Conf[app_name][:ruby] != 'auto'
          commands << "source '#{Etc.getpwuid.dir}/.rvm/scripts/rvm'"
          commands << "rvm #{v ? 'use ' : ''}'#{Conf[app_name][:ruby]}'"
        end
        commands << "cd '#{Conf[app_name][:app_path]}'"
        case Conf[app_name][:app_server]
        when 'passenger'
          commands << "passenger start -e production -p #{Conf[app_name][:port]} #{Conf[app_name][:app_server_options]} -d"
        when 'thin'
          commands << "thin start -e production -p #{Conf[app_name][:port]} #{Conf[app_name][:app_server_options]} -d"
        end
        print "Starting '#{app_name}' application..."
        STDOUT.flush
        output = `bash -c "#{commands.join(' && ')}"`
        puts ' done.'
        print output if v
      end
    end
  end

  def self.stop(argv)
    v, help = common_options(argv)
    if help
      puts 'Stop a web application added with ADD command. If no params are given stop all web applications.'
      exit
    end
    applications = argv
    applications = Conf.applications.keys if argv.empty?
    applications.each do |app_name|
      if Conf[app_name]
        commands = []
        if Conf[app_name][:ruby] != 'auto'
          commands << "source '#{Etc.getpwuid.dir}/.rvm/scripts/rvm'"
          commands << "rvm #{v ? 'use ' : ''}'#{Conf[app_name][:ruby]}'"
        end
        commands << "cd '#{Conf[app_name][:app_path]}'"
        case Conf[app_name][:app_server]
        when 'passenger'
          commands << "passenger stop -p #{Conf[app_name][:port]}"
        when 'thin'
          commands << "thin stop -p #{Conf[app_name][:port]}"
        end
        print "Stopping '#{app_name}' application..."
        STDOUT.flush
        output = `bash -c "#{commands.join(' && ')}"`
        puts ' done.'
        print output if v
      end
    end
  end

  def self.restart(argv)
    applications = argv
    applications = Conf.applications.keys if argv.empty?
    applications.each do |app_name|
      self.stop([app_name])
      self.start([app_name])
    end
  end

  def self.add(argv)
    options = {}
    tmp = argv.join('$$').split(/\$\$--\$\$/)
    argv = tmp[0].split('$$')
    options[:app_server_options] = tmp[1] ? tmp[1].split('$$').join(' ') : ''
    servers = ['passenger', 'thin']
    ports   = (3000..4000).to_a.collect{|p| p.to_s}
    options[:app_server] = servers.first
    options[:app_path]   = '/var/sites/APP_NAME/current'
    options[:port]       = nil
    options[:ruby]       = 'auto'
    options[:vhost_path] = '/etc/apache2/sites-available'
    vhost_template       = "#{Etc.getpwuid.dir}/.magicmonkey.yml"
    force                = false
    create_vhost         = true
    enable_site          = true
    reload_apache        = false
    server_name          = nil

    parser = OptionParser.new do |opts|
      opts.banner = 'Usage: magicmonkey add APP_NAME [options] [-- application_server_options]'
      opts.separator ''
      opts.separator 'Options:'

      opts.on('-s', '--app-server APP_SERVER', servers, "Use the given application server: #{servers.join(', ')} (default: #{options[:app_server]}).") do |s|
        options[:app_server] = s
      end
      opts.on('--app-path APP_PATH', "Use the given application path (default: '#{options[:app_path]}').") do |path|
        options[:app_path] = path
      end
      opts.on('--vhost-path VHOST_PATH', "Use the given virtual host path (default: '#{options[:vhost_path]}').") do |path|
        options[:vhost_path] = path
      end
      opts.on('--vhost-template TEMPLATE', "Use the given virtual host template file (default: #{vhost_template}).") do |template|
        vhost_template = template
      end
      opts.on('-p', '--port NUMBER', ports, "Use the given port number (min: #{ports.first}, max: #{ports.last}).") do |p|
        options[:port] = p.to_i
      end
      opts.on('-r', '--ruby RUBY_VERSION', "Use the given Ruby version (default: auto).") do |r|
        options[:ruby] = r
      end
      opts.on('-f', '--[no-]force', "Force mode: replace exist files (default: #{force}).") do |f|
        force = f
      end
      opts.on('--[no-]create-vhost', "Create virtual host file from template (default: #{create_vhost}).") do |c|
        create_vhost = c
      end
      opts.on('--[no-]enable-site', "Enable Apache virtual host (default: #{enable_site}).") do |e|
        enable_site = e
      end
      opts.on('--[no-]reload-apache', "Reload apache to load virtual host (default: #{reload_apache}).") do |r|
        reload_apache = r
      end
      opts.on('--server-name SERVER_NAME', "Set ServerName on virtual host (default: APP_NAME).") do |name|
        server_name = name
      end
      opts.on_tail('-h', '--help', 'Show this help message.') do
        puts opts
        exit
      end
    end
    begin
      argv = parser.parse!(argv)
    rescue
      puts parser.help
      exit
    end
    if argv.size != 1
      puts parser.help
      exit
    end
    app_name = argv[0]
    #setting up default values
    options[:app_path].gsub!('APP_NAME', app_name)
    port = get_port(options[:port])
    if port
      options[:port] = port
    else
      puts 'This port is busy'
      exit
    end
    #start
    if Conf[app_name].nil?
      Conf[app_name] = options
      puts "Configuration for application '#{app_name}' is:"
      pp Conf[app_name]
      print 'Add this application? [Y/n]'
      input = STDIN.gets
      if input.upcase == "Y\n" || input == "\n"
        if create_vhost
          vh = YAML.load_file(vhost_template)[:vhost_template]
          vh.gsub!('$APP_NAME', app_name)
          vh.gsub!('$SERVER_NAME', server_name || app_name)
          #vh.gsub!('$DOCUMENT_ROOT', Conf[app_name][:app_path])
          vh.gsub!('$PORT', Conf[app_name][:port].to_s)
          vh_file = "#{Conf[app_name][:vhost_path]}/#{app_name}"
          if !File.exist?(vh_file) || force
            #File.open(vh_file, 'w') { |f| f.write(vh) }
            print `sudo bash -c "echo '#{vh}' > #{vh_file}"`
          else
            puts "Virtual host file '#{vh_file}' already exist. Use option '-f' to replace it."
            exit
          end
          print `sudo a2ensite '#{app_name}'` if enable_site
          print `sudo /etc/init.d/apache2 reload` if enable_site && reload_apache
        end
        Conf.save
        puts 'Application added.'
      else
        puts 'Application rejected.'
      end
    else
      puts "Application '#{app_name}' already added. You can remove it with 'remove' command."
    end
  end

  def self.remove(argv)
    argv.each do |app_name|
      if Conf[app_name]
        vh_file = "#{Conf[app_name][:vhost_path]}/#{app_name}"
        if File.exist?(vh_file)
          print `sudo a2dissite '#{app_name}'`
          print `sudo rm -f #{vh_file}`
        end
        Conf.delete(app_name)
        Conf.save
      else
        puts "Application '#{app_name}' does not exist. You can add it with 'add' command."
      end
    end
  end

  private

  def self.get_port(port)
    ports = Conf.ports
    return 3000 if ports.nil? || ports.empty?
    return false if ports.include?(port)
    return ports.max + 1 if port.nil?
    return port
  end

  def self.common_options(argv)
    verbose = argv.include?('-v') || argv.include?('--version')
    help = argv.include?('-h') || argv.include?('--help')
    argv.delete('-v')
    argv.delete('--version')
    argv.delete('-h')
    argv.delete('--help')
    return verbose, help
  end

end