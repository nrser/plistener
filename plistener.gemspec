# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'plistener/version'

Gem::Specification.new do |spec|
  spec.name        = 'plistener'
  spec.version     = Plistener::VERSION
  spec.date        = '2015-02-28'
  spec.summary     = "watch OSX plist preference files and record changes"
  spec.description = <<-EOS
this is alpha-as-fuck. please use with caution.

it watches preference files stored as `.plist` on OSX and reports changes.
EOS
  spec.authors     = ["Neil Souza"]
  spec.email       = 'neil@neilsouza.com'
  spec.homepage    =
    'https://github.com/nrser/plistener'
  spec.license       = 'BSD'

  # spec.files       = ["lib/plistener.rb"]
  spec.files         = `git ls-files -z`.split("\x0")

  # s.executables << 'plistener'
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.6"
  spec.add_development_dependency "rake"

  spec.add_dependency 'listen', '~> 2.7'
  spec.add_dependency 'hashdiff', '~> 0.2'
  spec.add_dependency 'diffable_yaml', '~> 0.0'
  spec.add_dependency 'CFPropertyList', '~> 2.2'
end