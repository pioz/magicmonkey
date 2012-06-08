module Thin

  def self.start(args = {})
    ["thin start -e production -p #{args[:port]} #{args[:app_server_options]} -d"]
  end

  def self.stop(args = {})
    ["thin stop -p #{args[:port]}"]
  end

end