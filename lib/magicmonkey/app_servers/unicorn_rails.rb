module UnicornRails

  def self.start(args = {})
    ["unicorn_rails -E production -p #{args[:port]} #{args[:app_server_options]} -D"]
  end

  def self.stop(args = {})
    ["kill `ps ax | grep -v grep | grep -e 'unicorn_rails .*-p #{args[:port]}' | awk 'NR==1{print $1}'` || true"]
  end

end