#RPM Repository Metadata module
#Mix for RPM::Repository to work witn MD

module RPM::Repository::Metadata
private
  
  #Rebuild repository with current configuration with additional args and block - synced
  def rebuild_with args = ""
    synchronize {
      yield if block_given?
      @status = :rebuilding
      #TODO: add group file to rebuilding
      unless system "createrepo -v --profile --update #{@base_dir.path} -s #{get_checksum_type} #{@extended_rebuild_args} #{args} &> '#{@tmp_dir.path}/rebuild-#{Time.now.to_s}'"
        raise RuntimeError, "Can't rebuild repository #{@name}"
      end
      @status = :ok
    }
    @logger.info "rebuilded"
    return true
  end
  
  #read and parse repomd.xml - UNSYNC! - low level operation - no reason to make locks
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
  
  #Get checksum type from repomd.xml to be used for correct rebuilding - UNSYNC!!!
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
  
  #MD-related initialization part
  def initialization_metadata rebuild_args
    #Default additional arguments for createrepo
    @extended_rebuild_args = rebuild_args
  end
  
end
