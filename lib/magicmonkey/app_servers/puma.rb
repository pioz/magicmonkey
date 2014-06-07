module Puma

  def self.start(args = {})
    ["puma -e production -p #{args[:port]} --pidfile 'tmp/pids/puma.pid' #{args[:app_server_options]} -d"]
  end

  def self.stop(args = {})
    ["kill `cat 'tmp/pids/puma.pid'`"]
  end

end