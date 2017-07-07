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
    
    #Add packages to repository by URL (may be file or http source)
    def add_package! pkg
      add_packages! [pkg]
    end
    
    def add_packages! pkgs
      @logger.info "adding packages"
      duplicated_packages = []
      rebuild_with {
        pkgs.each { |pkg|
          pkg.duplicate_to "#{@base_dir.path}/Packages" if pkg.get_local_uris_undo(@base_dir.path).empty?
          duplicated_packages.push pkg
        }
      }
    rescue Exception => e
      rebuild_with {
        duplicated_packages.each { |pkg|
          pkg.deduplicate_undo "#{@base_dir.path}/Packages"
        }
      }
      raise e
    end
    
    #Remove pkg by URL strings
    def remove_package! pkg_url
      @logger.info "removing package"
      raise ArgumentError, "No such package in repository: #{pkg_url.to_s}" if get_pkg_list.select{|pkg| pkg.get_local_uris_undo(@base_dir.path).first == pkg_url}.empty?
      rebuild_with("-x #{pkg_url.to_s}"){
        FileUtils::remove "#{pkg_url.path}" if File.exist? pkg_url.path
      }
    end
    
    #Remove pkgs by url string list
    #Return two arrays: removed and skipped packages
    def remove_packages! pkgs_urls
      @logger.info "removing packages"
      rezult = {:removed => [], :skipped => []}
      current_pkg_list = get_pkg_list
      @locker.synchronize {
        pkgs_urls.each { |pkg_url|
          if current_pkg_list.select{|pkg| pkg.get_local_uris_undo(@base_dir.path).first == pkg_url}.empty?
            rezult[:skipped].push pkg_url
            @logger.warn "Package #{pkg_url} skipped while removal"
          else
            rezult[:removed].push pkg_url
            FileUtils::remove "#{pkg_url.path}" if File.exist? pkg_url.path
          end
        }
      }
      rebuild_with rezult[:removed].collect{|pkg_url|"-x #{pkg_url.to_s}"}.join(' ')
      return rezult
    end
    
    #Remove packages by regex
    #Return list with removed URL's
    def parse_out_pkgs! pkg_name_expr
      return remove_packages! get_package_list_by(pkg_name_expr)
    end
    
    #Return package URL's array that match parameter
    def get_package_list_by pkg_name_expr
      get_pkg_list.select{ |pkg| pkg.get_default_name[pkg_name_expr] }.collect{|pkg| pkg.get_local_uris_undo(@base_dir.path).first }
    end
    
    #return true if repository contains package with same signature
    def contains? alien_pkg
      not get_pkg_list.select{ |pkg| pkg.same_as? alien_pkg }.empty?
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
    
    #return pkgs list
    def get_pkg_list
      refresh_pkg_cache
      get_packages_from_cache
    end
    
    #Public and safe realization of rebuilding - just rebuild repository
    def rebuild
      rebuild_with
    end
    
  private
  
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
      @locker.synchronize {
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
      }
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
