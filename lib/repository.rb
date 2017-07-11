#Local RPM repository with packages

module RPM
  class Repository < Monitor
    
    require_relative 'repository_api'
    require_relative 'repository_caching'
    require_relative 'repository_metadata'
    
    attr_reader :base_dir
    attr_reader :status
    attr_reader :tmp_dir
    attr_accessor :name
    
    @@statuses = {
      :initializing => "Repository initialization in progress",
      :rebuilding => "Rebuild repository metadata",
      :destroying => "Repository destruction in progress",
      :destroyed => "Repository removed and not available",
      :ok => "Repository in normal state",
      :cleaning => "Cleaning up temporary data"
    }
    
    #Init repository in specified directory
    def initialize base_dir, name = SecureRandom.uuid, rebuild_args = ""
      #Call Monitor's contructor to initialize it
      super()
      synchronize {
        @status = :initializing
        #Human-readable repo name (default here, but available from the outside)
        @name = name
        #Logging
        @logger = Logging.logger['repo ' + @name]
        @logger.debug 'initializing'
        #Local basic directory 
        raise ArgumentError, "Base directory must be non-relative" if base_dir.nil? or not base_dir[/^\/.+/]
        FileUtils::mkdir_p base_dir, { :mode => 0700 } unless Dir.exist? base_dir
        @base_dir = Dir.new base_dir
        File.chmod 0700, @base_dir.path
        #Dir for some tmp files
        Dir.mkdir @base_dir.path + "/tmp" unless Dir.exist? @base_dir.path + "/tmp"
        @tmp_dir = Dir.new @base_dir.path + "/tmp"
        #Init repository
        FileUtils::mkdir "#{@base_dir.path}/Packages", { :mode => 0700 } unless @base_dir.entries.include? "Packages"
        #Parts-relates initialization
        initialization_metadata rebuild_args
        initialization_cache
        @logger.info "initialized"
        #Making MD
        rebuild
        #Cache warming
        validate_packages_cache
        @status = :ok
      }
    end
    
    #include MonitorMixin
    
    #Include substructures
    include RPM::Repository::Metadata
    include RPM::Repository::Caching
    include RPM::Repository::API
    
  private
    
    #Return Package URI in current repository
    def get_own_uri package
      same_packages = get_packages_list.select { |repo_package| repo_package.same_as? package }
      case same_packages.count
      when 1
        return (same_packages.first.get_local_uris_undo "#{@base_dir.path}/Packages").first
      when 0
        return nil
      else
        raise RuntimeError, "More than one #{package.get_default_name} package in repository"
      end
    end
    
  end
end
