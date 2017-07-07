#Attempt to sync concurrent managing of multiple repositories

module RPM
    
    class RepoFactory
        
        def initialize
            @locker = Mutex.new
            @locker.synchronize {
                #Logging - now not needed
                #@logger = Logging.logger['repo ' + @name]
                #@logger.debug 'initializing'
                @repositories = []
            }
        end
        
        #Synced repository adding
        def add_repository repository
            @locker.synchronize {
                if repository.kind_of? RPM::Repository
                    if (get_repository_by repository.name).is_a? RPM::Repository
                        raise ArgumentError, "Repository with such name already exist!"
                    end
                    @repositories.push repository
                    return true
                else
                    return false
                end
            }
        end
        
        #Synced repository removal and destroying
        def destroy_repository_by! name
            repo = get_repository_by name
            return false if repo.nil?
            repo.destroy!
            @locker.synchronize {
                @repositories.delete repo
            }
            return true
        end
        
        #the way to non-block reading
        def get_repositories
            @repositories.clone
        end
        
        #Return repository by name
        def get_repository_by name
            unless name.kind_of? String
                return nil
            end
            possible_repos = get_repositories.select { |repo| repo.name == name }
            case possible_repos.count
                when 1
                    return possible_repos.first
                else
                    return nil
            end
        end
        
        #wrap over Array's each
        def each
            get_repositories.each { |repository| yield repository if block_given? }
        end
        
    end
    
end
