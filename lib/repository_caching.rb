#RPM Repository Caching module
#Mix for RPM::Repository to realize MD in-memory caching

module RPM::Repository::Caching
private
  
  #Return values from cached packages list - UNSYNC!!!
  def get_packages_from_cache
    @packages_cache.values
  end
  
  #Check that current package list cache valid. if not - validate
  def validate_packages_cache
    @logger.debug "validating packages cache"
    synchronize {
      if repomd_cache_hit?
        @logger.debug "MD cache hit"
        return true
      else
        refresh_md_files_cache
        refresh_packages_cache
        return true
      end
    }
  end
  
  #All below used just once. In case of multithreading usage - sync it by synchronize { body }
  
  #true means 100% hit in cached repository state - UNSYNC!!! - used once
  def repomd_cache_hit?
    if @repomd_cache.is_a? REXML::Document
      return read_repomd_doc.elements["/repomd/revision"].text == @repomd_cache.elements["/repomd/revision"].text
    else
      return false
    end
  end
  
  #refreshing each md file cach
  def refresh_md_files_cache
    @repomd_cache = read_repomd_doc
    @md_content_cache.keys.each { |type|
      @md_content_cache[type] = read_md_doc type.to_s
    }
  end
  
  #Actually check packages cache: remove aol packges and add new
  def refresh_packages_cache
      #save current cache state
      prev_cache = @packages_cache
      #clean current cache
      @packages_cache = {}
      @md_content_cache[:primary].each_element('/metadata/package') { |package_md|
        chksum = package_md.elements['checksum'].text
        if prev_cache[chksum]
          #get package from previous cache
          @packages_cache[chksum] = prev_cache[chksum]
        else
          #construct new one
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
  end
  
end
