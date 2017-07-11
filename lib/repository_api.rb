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
    rebuild_with("-x #{get_own_uri(package).to_s}"){
      raise ArgumentError, "No such package in repository: #{package.get_default_name}" unless contains? package
      FileUtils::remove get_own_uri(package).path
    }
  end
  
  #Remove packages
  #Return two arrays: {:removed => [...], :skipped => [...]}
  def remove_packages! packages
    @logger.info "removing packages"
    rezult = {:removed => [], :skipped => []}
    synchronize {
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
      rebuild_with rezult[:removed].collect{ |package| "-x #{get_own_uri(package).to_s}" }.join(' ')
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
  
end
