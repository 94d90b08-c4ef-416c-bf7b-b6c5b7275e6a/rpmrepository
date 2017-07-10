Gem::Specification.new do |s|
  s.name        = 'rpmrepository'
  s.version     = '0.0.2'
  s.summary     = "Deal with RPM Repository/Package"
  s.description = "Gem to create/manage RPM repository(ies)/package(s)"
  s.authors     = ["nothing"]
  s.files       = ["lib/rpm.rb","lib/package.rb","lib/repository.rb","lib/repofactory.rb",]
  s.license     = 'Beerware'
  s.add_runtime_dependency 'logging'
end
