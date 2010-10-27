require 'optparse'
require 'pp'
require 'etc'
require "#{$APP_PATH}/lib/configuration"

module MagicMonkey
  COMMANDS = [:start, :stop, :restart, :add, :remove, :show]

  def self.main(argv)
    #raise 'Must run as root' unless Process.uid == 0
    command = argv[0]
    if command.nil? || command == '-h' || command == '--help' || !COMMANDS.include?(command.to_sym)
      main_help
      exit
    elsif command == '-v' || command == '--version'
      puts File.exist?("#{$APP_PATH}/VERSION") ? File.read("#{$APP_PATH}/VERSION").strip : ''
      exit
    else
      send(command, argv[1..-1])
    end
  end

  def self.main_help
    puts 'Desj'
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
    applications = argv
    applications = Conf.applications.keys if argv.empty?
    applications.each do |app_name|
      if Conf[app_name]
        commands = []
        commands << "source '#{Etc.getpwuid.dir}/.rvm/scripts/rvm'"
        commands << "cd '#{Conf[app_name][:app_path]}'"
        commands << "rvm use '#{Conf[app_name][:ruby]}'"
        case Conf[app_name][:app_server]
        when 'passenger'
          commands << "passenger start -e production -p #{Conf[app_name][:port]} -d"
        when 'thin'
          commands << "thin start -e production -p #{Conf[app_name][:port]} -d"
        end
        print `#{commands.join(' && ')}`
      end
    end
  end
  
  def self.stop(argv)
    applications = argv
    applications = Conf.applications.keys if argv.empty?
    applications.each do |app_name|
      if Conf[app_name]
        commands = []
        commands << "cd '#{Conf[app_name][:app_path]}'"
        case Conf[app_name][:app_server]
        when 'passenger'
          commands << "passenger stop -p #{Conf[app_name][:port]}"
        when 'thin'
          commands << "thin stop -p #{Conf[app_name][:port]}"
        end
        print `#{commands.join(' && ')}`
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
    servers = ['passenger', 'thin']
    ports   = (3000..4000).to_a.collect{|p| p.to_s}
    rubies  = ['default', '1.9.2', '1.8.7', 'ree']
    options = {}
    options[:app_server] = servers.first
    options[:app_path]   = '/var/sites/APP_NAME/current'
    options[:port]       = nil
    options[:ruby]       = rubies.first
    options[:vhost_path] = '/etc/apache2/sites-avaiable'
    vhost_template       = "#{Etc.getpwuid.dir}/.magicmonkey.yml"
    force                = false
    create_vhost         = true
    enable_site          = true
    reload_apache        = false
    server_name          = nil
    
    
    parser = OptionParser.new do |opts|
      opts.banner = 'Usage: magicmonkey add APP_NAME [options]'
      opts.separator ''
      opts.separator 'Options:'


      opts.on('-s', '--app-server APP_SERVER', servers, "Use the given application server: #{servers.join(', ')} (default #{options[:app_server]}).") do |s|
        options[:app_server] = s
      end
      
      opts.on('--app-path APP_PATH', "Use the given application path (default '#{options[:app_path]}').") do |path|
        options[:app_path] = path
      end
      
      opts.on('--vhost-path VHOST_PATH', "Use the given virtual host path (default '#{options[:vhost_path]}').") do |path|
        options[:vhost_path] = path
      end
      
      opts.on('--vhost-template TEMPLATE', "Use the given virtual host template file.") do |template|
        vhost_template = template
      end
      
      opts.on('-p', '--port NUMBER', ports, "Use the given port number (min: #{ports.first}, max: #{ports.last}).") do |p|
        options[:port] = p.to_i
      end
    
      opts.on('-r', '--ruby RUBY_VERSION', rubies, "Use the given Ruby version: #{rubies.join(', ')} (default #{options[:ruby]}).") do |r|
        options[:ruby] = r
      end
    
      opts.on('-f', '--[no-]force', "Force mode: replace exist files.") do |f|
        force = f
      end
      
      opts.on('--[no-]create-vhost', "Create virtual host file from template (default true).") do |c|
        create_vhost = c
      end
      
      opts.on('--[no-]enable-site', "Enable Apache virtual host (default true).") do |e|
        enable_site = e
      end
      
      opts.on('--[no-]reload-apache', "Reload apache to load virtual host (default false).") do |r|
        reload_apache = r
      end
      
      opts.on('--server-name SERVER_NAME', "Set ServerName on virtual host.") do |name|
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
      print "Add this application? [Y/n]"
      input = STDIN.gets
      if input.upcase == "Y\n" || input == "\n"
        if create_vhost
          vh = YAML.load_file(vhost_template)[:vhost_template]
          vh.gsub!('$SERVER_NAME', server_name || app_name)
          vh.gsub!('$DOCUMENT_ROOT', Conf[app_name][:app_path])
          vh.gsub!('$PORT', Conf[app_name][:port].to_s)
          vh_file = "#{Conf[app_name][:vhost_path]}/#{app_name}"
          if !File.exist?(vh_file) || force
            #File.open(vh_file, 'w') { |f| f.write(vh) }
            print `sudo echo '#{vh}' > #{vh_file}`
          else
            puts "Virtual host file '#{vh_file}' already exist. Use option '-f' to replace it."
            exit
          end
          print `sudo a2ensite '#{vh_file}'` if enable_site
          print `sudo /etc/init.d/apache2 reload` if enable_site && reload_apache
        end
        Conf.save
        puts "Application added."
      else
        puts "Application rejected."
      end
    else
      puts "This application already added. You can remove it with 'remove' command."
    end
  end
  
  def self.remove(argv)
    argv.each do |app_name|
      if Conf[app_name]
        vh_file = "#{Conf[app_name][:vhost_path]}/#{app_name}"
        if File.exist?(vh_file)
          print `sudo a2dissite '#{vh_file}'`
          print `sudo rm -f #{vh_file}`
        end
        Conf.delete(app_name)
        Conf.save
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

end