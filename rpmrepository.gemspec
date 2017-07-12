Gem::Specification.new do |s|
  s.name        = 'rpmrepository'
  s.version     = '0.0.3'
  s.summary     = "Deal with RPM Repository/Package"
  s.description = "Gem to create/manage RPM repository(ies)/package(s)"
  s.authors     = ["nothing"]
  s.files       = [
                    "lib/rpm.rb",
                    "lib/package.rb",
                    "lib/repository.rb",
                    "lib/repository_api.rb",
                    "lib/repository_caching.rb",
                    "lib/repository_metadata.rb",
                    "lib/repofactory.rb",
                  ]
  s.license     = 'Beerware'
  s.add_runtime_dependency 'logging'
end
