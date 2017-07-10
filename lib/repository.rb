#Local RPM repository with packages

module RPM
  
  class Repository
    
    attr_reader :base_dir
    attr_reader :status
    attr_reader :tmp_dir
    attr_accessor :name
    
    #Init repository in specified directory
    def initialize base_dir, name = 'YUM Repository', rebuild_args = ""
      @locker = Mutex.new
      @locker.synchronize {
        #Human-readable repo name (default here, but available from the outside)
        @name = name
        #Logging
        @logger = Logging.logger['repo ' + @name]
        @logger.debug 'initializing'
        #Extended rebuild args
        @extended_rebuild_args = rebuild_args
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
        #Cache-related structures
        #cached and parsed main XML MD
        @repomd_cache = nil
        #cached and parsed XML documents
        @md_content_cache = { :primary => nil }
        #checksum => RPM::Package
        @packages_cache = {}
        @logger.info "initialized"
      }
      rebuild
      refresh_pkg_cache
    end
    
    #Package magic
    
    #Add single package to repository
    def add_package! package
      add_packages! [package]
    end
    
    #Add packages to repository
    def add_packages! packages
      @logger.info "adding packages"
      duplicated_packages = []
      packages.each { |package|
       raise ArgumentError, "Package expected, but #{package.class}" unless package.is_a? RPM::Package
       raise RuntimeError, "Package already exist!" if contains? package
      }
      rebuild_with {
        packages.each { |package|
          package.duplicate_to "#{@base_dir.path}/Packages"
          duplicated_packages.push package
        }
      }
    rescue Exception => e
      rebuild_with {
        duplicated_packages.each { |package|
          package.deduplicate_undo "#{@base_dir.path}/Packages"
        }
      }
      raise e
    end
    
    #Remove package
    def remove_package! package
      @logger.info "removing package"
      raise ArgumentError, "No such package in repository: #{package.get_default_name}" unless contains? package
      rebuild_with("-x #{get_own_uri(package).to_s}"){
        FileUtils::remove get_own_uri(package).path
      }
    end
    
    #Remove packages
    #Return two arrays: {:removed => [...], :skipped => [...]}
    def remove_packages! packages
      @logger.info "removing packages"
      rezult = {:removed => [], :skipped => []}
      @locker.synchronize {
        packages.each { |package|
          #contains? is unsafe for transpatrent repository state: file existance check required
          if contains? package and File.exist? get_own_uri(package).path
            rezult[:removed].push package
            FileUtils::remove get_own_uri(package).path
          else
            rezult[:skipped].push package
            @logger.warn "Package #{package} skipped: no such package in repository"
          end
        }
      }
      rebuild_with rezult[:removed].collect{|package|"-x #{get_own_uri(package).to_s}"}.join(' ')
      return rezult
    end
    
    #Remove packages by regex
    #Return list with removed URL's
    def parse_out_packages! name_expression
      return remove_packages! get_packages_list_by(name_expression)
    end
    
    #Return packages array that match parameter
    def get_packages_list_by name_expression
      get_packages_list.select{ |package| package.get_default_name[name_expression] }
    end
    
    #Return true if repository contains package with same signature
    def contains? alien_package
      not get_packages_list.select{ |package| package.same_as? alien_package }.empty?
    end
    
    #Remove repository files
    def destroy!
      @logger.info "destroying repo"
      return @status if @status == :destroyed
      @locker.synchronize {
        clean
        FileUtils::rm_rf @base_dir.path
        @status = :destroyed
      }
    end
    
    #Cleanup temporary files
    def clean
      @logger.info "cleaning repo"
      FileUtils::rm_rf @tmp_dir.path
      FileUtils::mkdir @tmp_dir.path
    end
    
    #Return template for YUM configuration
    def get_local_conf
      "
      [#{@name}]
      name=#{@name}
      baseurl=file:///#{@base_dir.path}
      gpgcheck=0
      enabled=0
      "
    end
    
    #return list of packages
    def get_packages_list
      refresh_pkg_cache
      get_packages_from_cache
    end
    
    #Public and safe realization of rebuilding - just rebuild repository
    def rebuild
      rebuild_with
    end
    
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
    #rebuild repository by current configuration with additional args and block
    #all synced
    def rebuild_with args = ""
      @logger.debug "rebuilding"
      @locker.synchronize {
        yield if block_given?
        @status = :rebuilding
        #TODO: add group file to rebuilding
        unless system "createrepo -v --profile --update #{@base_dir.path} #{args} #{@extended_rebuild_args} -s #{get_checksum_type} &> '#{@tmp_dir.path}/rebuild-#{Time.now.to_s}'"
          raise RuntimeError, "Can't rebuild repository #{@name}"
        end
        @status = nil
      }
      @logger.info "rebuilded"
      return true
    end
    
    #caching workhouse
    #Return values from cached packages list - sync-safe
    def get_packages_from_cache
      @packages_cache.values
    end

    #Check that current package list cache valid. if not - validate
    def refresh_pkg_cache
      @logger.debug "refreshing packages cache info"
      if @locker.locked?
        unless @locker.owned?
          while @locker.locked?
            sleep 10
          end
          @locker.lock
          self_lock = true
        end
      else
        @locker.lock
        self_lock = true
      end
        if repomd_cache_hit?
          @logger.debug "MD cache hit"
          return true
        else
          @logger.debug 'refreshing md'
          #refreshing each cache file
          @repomd_cache = read_repomd_doc
          @md_content_cache.keys.each { |type|
            @md_content_cache[type] = read_md_doc type.to_s
          }
          @logger.debug 'refreshing packages'
          #reafreshing packages list
          prev_cache = @packages_cache
          @packages_cache = {}
          @md_content_cache[:primary].each_element('/metadata/package') { |package_md|
            chksum = package_md.elements['checksum'].text
            if prev_cache[chksum]
              @packages_cache[chksum] = prev_cache[chksum]
            else
              url = ''
              if package_md.elements['location'].attributes["xml:base"]
                url = URI::parse (package_md.elements['location'].attributes["xml:base"]+'/'+package_md.elements['location'].attributes["href"])
              else
                url = URI::parse ('file://' + @base_dir.path+'/'+package_md.elements['location'].attributes["href"])
              end
              @packages_cache[chksum] = RPM::Package.new url
            end
          }
          @logger.debug 'package cache refreshed'
          return true
        end
    ensure
      @locker.unlock if @locker.owned? and self_lock
    end
    
    #metadata workhouse
    #true means 100% hit in cached repository state
    def repomd_cache_hit?
      if @repomd_cache.is_a? REXML::Document
        return read_repomd_doc.elements["/repomd/revision"].text == @repomd_cache.elements["/repomd/revision"].text
      else
        return false
      end
    end
    
    #read and parse repomd.xml - UNSYNC!
    def read_repomd_doc
      REXML::Document.new File.open(@base_dir.path + "/repodata/repomd.xml")
    end
    
    #return md file document by type - UNSYNC!
    #assume that @repomd_cache is valid
    def read_md_doc type
      @logger.debug "getting #{type} md file"
      if @repomd_cache.elements["/repomd/data[@type=\"#{type}\"]/location"].attributes["href"]
        path_to_md_file = @base_dir.path+'/'+@repomd_cache.elements["/repomd/data[@type=\"#{type}\"]/location"].attributes["href"]
        #raw_md_file = File.read path_to_md_file
        case path_to_md_file
        when /\.gz$/
          Zlib::GzipReader.open(path_to_md_file) { |gz|
            return REXML::Document.new gz.read
          }
        when /\.xml$/
          return REXML::Document.new File.read path_to_md_file
        else
          raise RuntimeError, "Can't determine type of #{path_to_md_file}"
        end
      else
        raise ArgumentError, 'No #{type} md file record in repomd.xml'
      end
    end
    
    #parse checksum type from repomd.xml to correct rebuilding
    def get_checksum_type
      #@logger.debug "getting checksum type"
      if File::exist? (@base_dir.path + "/repodata/repomd.xml")
        repomd_doc = read_repomd_doc
        if repomd_doc.elements["/repomd/data/checksum"].attributes["type"]
          return repomd_doc.elements["/repomd/data/checksum"].attributes["type"]
        else
          #if no such field (improbable)
          return "sha256"
        end
      else
        #if this is fresh repository
        return "sha256"
      end
    end
    
  end
  
end
