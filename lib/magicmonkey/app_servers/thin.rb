module Thin

  def self.start(args = {})
    bundle_exec = 'bundle exec ' if args[:bundle_exec]
    return "#{bundle_exec}thin start -e production -p #{args[:port]} #{args[:app_server_options]} -d"
  end

  def self.stop(args = {})
    bundle_exec = 'bundle exec ' if args[:bundle_exec]
    return "#{bundle_exec}thin stop -p #{args[:port]}"
  end

  def self.restart(args = {})
    [self.stop(args), 'sleep 3', self.start(args)]
  end

end