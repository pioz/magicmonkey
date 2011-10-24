module Passenger

  def self.start(args = {})
    return "passenger start -e production -p #{args[:port]} #{args[:app_server_options]} -d"
  end

  def self.stop(args = {})
    return 'passenger stop'
  end

end