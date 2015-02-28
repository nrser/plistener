Gem::Specification.new do |s|
  s.name        = 'plistener'
  s.version     = '0.0.1'
  s.date        = '2015-02-28'
  s.summary     = "watch OSX plist preference files and record changes"
  s.description = <<-EOS
this is alpha-as-fuck. please use with caution.

it watches preference files stored as `.plist` on OSX and reports changes.
EOS
  s.authors     = ["Neil Souza"]
  s.email       = 'neil@neilsouza.com'
  s.files       = ["lib/plistener.rb"]
  s.homepage    =
    'https://github.com/nrser/plistener'
  s.license       = 'BSD'
  s.add_dependency 'listen', '~> 2.7'
  s.add_dependency 'hashdiff', '~> 0.2'
  s.add_dependency 'diffable_yaml', '~> 0.0'
  s.add_dependency 'CFPropertyList', '~> 2.2'
  s.executables << 'plistener'
end