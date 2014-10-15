module UnicornRails

  def self.start(args = {})
    ["unicorn_rails -E production -p #{args[:port]} #{args[:app_server_options]} -D"]
  end

  def self.stop(args = {})
    ## QUIT - graceful shutdown, waits for workers to finish their current request before finishing. from http://unicorn.bogomips.org/SIGNALS.html
    ["kill -QUIT `ps ax | grep -v grep | grep -e '[u]nicorn_rails master .*-p #{args[:port]}' | awk 'NR==1{print $1}'` || true"]
  end

end
