module UnicornRails

  def self.start(args = {})
    ["unicorn_rails -E production -p #{args[:port]} -c #{args[:app_path]}/config/unicorn.rb #{args[:app_server_options]} -D"]
  end

  def self.stop(args = {})
    ["kill `ps ax | grep -v grep | grep -e 'unicorn_rails .*-p #{args[:port]}' | awk 'NR==1{print $1}'`"]
  end

end