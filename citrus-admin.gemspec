# Author:: MinixLi (gmail: MinixLi1986)
# Homepage:: http://citrus.inspawn.com
# Date:: 8 July 2014

$:.push File.expand_path('../lib', __FILE__)

require 'citrus-admin/version'

Gem::Specification.new do |spec|
  spec.name        = 'pomelo-citrus-admin'
  spec.version     = CitrusAdmin::VERSION
  spec.platform    = Gem::Platform::RUBY
  spec.authors     = ['MinixLi']
  spec.email       = 'MinixLi1986@gmail.com'
  spec.description = %q{pomelo-citrus-admin is a simple clone of pomelo-admin, it provides an admin module for pomelo monitor system}
  spec.summary     = %q{pomelo-admin clone written in Ruby using EventMachine}
  spec.homepage    = 'https://github.com/minixli/pomelo-citrus-admin'
  spec.license     = 'MIT'

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ['lib']

  spec.add_dependency('eventmachine', '~> 0')
  spec.add_dependency('json', '~> 0')
  spec.add_dependency('websocket-eventmachine-client', '~> 0')
  spec.add_dependency('websocket-eventmachine-server', '~> 0')

  spec.add_dependency('pomelo-citrus-loader', '~> 0')
  spec.add_dependency('pomelo-citrus-logger', '~> 0')
  spec.add_dependency('pomelo-citrus-monitor', '~> 0')
  spec.add_dependency('pomelo-citrus-scheduler', '~> 0')
end
