module Passenger

  def self.start(args = {})
    bundle_exec = 'bundle exec ' if args[:bundle_exec]
    return "#{bundle_exec}passenger start -e production -p #{args[:port]} #{args[:app_server_options]} -d"
  end

  def self.stop(args = {})
    bundle_exec = 'bundle exec ' if args[:bundle_exec]
    return "#{bundle_exec}passenger stop -p #{args[:port]}"
  end

  def self.restart(args = {})
    [self.stop(args), 'sleep 3', self.start(args)]
  end

end