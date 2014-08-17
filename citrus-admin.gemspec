# Author:: MinixLi (gmail: MinixLi1986)
# Homepage:: http://citrus.inspawn.com
# Date:: 8 July 2014

$:.push File.expand_path('../lib', __FILE__)

require 'citrus-admin/version'

Gem::Specification.new do |spec|
  spec.name        = 'citrus-admin'
  spec.version     = CitrusAdmin::VERSION
  spec.platform    = Gem::Platform::RUBY
  spec.authors     = ['MinixLi']
  spec.email       = 'MinixLi1986@gmail.com'
  spec.description = %q{Citrus Admin implemented in Ruby}
  spec.summary     = %q{Citrus Admin implemented in Ruby}
  spec.homepage    = 'http://citrus.inspawn.com'
  spec.license     = 'MIT'

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ['lib']

  spec.add_dependency('eventmachine')
  spec.add_dependency('json')
  spec.add_dependency('websocket-eventmachine-client')
  spec.add_dependency('websocket-eventmachine-server')

  spec.add_dependency('citrus-loader')
  spec.add_dependency('citrus-logger')
  spec.add_dependency('citrus-monitor')
  spec.add_dependency('citrus-scheduler')
end
