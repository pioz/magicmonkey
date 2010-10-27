require 'singleton'
require 'yaml'

class Conf
  include Singleton
  attr_reader :config

  def initialize
    load
  end

  def load
    @file = "/Users/pioz/Desktop/magicmonkey.yml"
    if File.exist?(@file)
      @config = YAML.load_file(@file)
    else
      vht = ""
      vht << "<VirtualHost tagi:80>\n"
      vht << "  ServerName $SERVER_NAME\n"
      vht << "  DocumentRoot $DOCUMENT_ROOT\n"
      vht << "  PassengerEnabled off\n"
      vht << "  ProxyPass / http://127.0.0.1:$PORT\n"
      vht << "  ProxyPassReverse / http://127.0.0.1:$PORT\n"
      vht << "</VirtualHost>\n"
      @config = {:vhost_template => vht}
      self.save
    end
  end
  
  def save
    File.open(@file, 'w') { |f| f.write(@config.to_yaml) }
    self.load
  end
  
  def self.[](key)
    Conf.instance.config[key.to_sym]
  end
  
  def self.[]=(key, value)
    Conf.instance.config[key.to_sym] = value
  end
  
  def self.delete(key)
    Conf.instance.config.delete(key.to_sym)
  end
  
  def self.save
    Conf.instance.save
  end
  
  def self.applications
    app = {}
    Conf.instance.config.each do |k, v|
      if k != :vhost_template
        app[k] = v
      end
    end
    return app
  end
  
  def self.ports
    p = []
    Conf.instance.config.each do |k, v|
      p << v[:port] if v[:port]
    end
    return p
  end
  
end