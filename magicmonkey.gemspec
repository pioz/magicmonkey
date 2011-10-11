# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "magicmonkey/version"

Gem::Specification.new do |s|
  s.name        = "magicmonkey"
  s.version     = Magicmonkey::VERSION
  s.authors     = ["Enrico Pilotto"]
  s.email       = ["enrico@megiston.it"]
  s.homepage    = "https://github.com/pioz/magicmonkey"
  s.summary     = %q{Manage your Rails applications: different Ruby versions and different application servers}
  s.description = %q{Manage your Rails applications: different Ruby versions and different application servers.}

  s.rubyforge_project = "magicmonkey"

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]
end
