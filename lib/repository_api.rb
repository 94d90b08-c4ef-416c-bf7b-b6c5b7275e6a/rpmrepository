#Public user api of RPM::Repository
#Should'n changed frequently

module RPM::Repository::API
  
  #Add single package to repository
  def add_package! package
    add_packages! [package]
  end
  
  #Add packages to repository
  def add_packages! packages
    @logger.info "adding packages"
    duplicated_packages = []
    rebuild_with {
      packages.each { |package|
        raise ArgumentError, "Package expected, but #{package.class}" unless package.is_a? RPM::Package
        raise RuntimeError, "Package already exist!" if contains? package
        package.duplicate_to "#{@base_dir.path}/Packages"
        #hack that add package to cache. Escape package brain splitting (two packages with the same file)
        if package.digests[get_checksum_type.to_sym]
          @packages_cache[package.digests[get_checksum_type.to_sym]] = package
        end
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
    rebuild_with {
      raise ArgumentError, "No such package in repository: #{package.get_default_name}" unless contains? package
      get_own(package).deduplicate_undo @base_dir.path
    }
  end
  
  #Remove packages
  #Return two arrays: {:removed => [...], :skipped => [...]}
  def remove_packages! packages
    @logger.info "removing packages"
    rezult = {:removed => [], :skipped => []}
    rebuild_with {
      packages.each { |package|
        if contains? package
          get_own(package).deduplicate_undo @base_dir.path
          rezult[:removed].push package
        else
          rezult[:skipped].push package
          @logger.warn "Package #{package} skipped: no such package in repository"
        end
      }
    }
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
  alias include? contains?
  
  #Try to expand package URIs with own
  #Return true if package expanded, false otherwise
  def assimilate! alien_package
    if contains? alien_package
      alien_package.join! get_own(alien_package)
      synchronize { @packages_cache[alien_package.digests[get_checksum_type.to_sym]] = alien_package }
      return true
    else
      return false
    end
  end
  
  #Remove repository files
  def destroy!
    @logger.info "destroying repo"
    return @status if @status == :destroyed
    synchronize {
      @status = :destroying
      clean
      FileUtils::rm_rf @base_dir.path
      @status = :destroyed
    }
  end
  
  #Cleanup temporary files
  def clean
    @logger.info "cleaning repo"
    synchronize {
      @status = :cleaning
      FileUtils::rm_rf @tmp_dir.path
      FileUtils::mkdir @tmp_dir.path
      @status = :ok
    }
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
  
  #Return array of packages
  def get_packages_list
    synchronize { validate_packages_cache && get_packages_from_cache }
  end
  
  #Public and safe realization of rebuilding - just rebuild repository
  def rebuild
    rebuild_with
  end
private
  
  #Return Package from current repository
  #Method not public because it brings packages split-brain (two same package into runtime)
  def get_own package
    same_packages = get_packages_list.select { |repo_package| repo_package.same_as? package }
    case same_packages.count
    when 1
      return same_packages.first
    when 0
      return nil
    else
      raise RuntimeError, "More than one #{package.get_default_name} package in repository"
    end
  end
  
end
