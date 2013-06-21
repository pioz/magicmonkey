module Passenger

  def self.start(args = {})
    ["passenger start -e production -p #{args[:port]} #{args[:app_server_options]} -d"]
  end

  def self.stop(args = {})
    ["passenger stop -p #{args[:port]} || true"]
  end

end