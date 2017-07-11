#One package with possible multiple locations

module RPM
    
    class Package < Monitor
        
        attr_reader :uris
        attr_reader :name
        attr_reader :version
        attr_reader :release
        attr_reader :architecture
        attr_reader :size
        attr_reader :file_size
        attr_reader :digests

        def initialize raw_uri
            super()
            synchronize {
              @uris = []
              raise ArgumentError, "Only String or URI" unless raw_uri.kind_of? String or raw_uri.kind_of? URI::Generic
              if raw_uri.kind_of? URI::Generic
                  uri = raw_uri.dup
              else
                  uri = URI::parse raw_uri
              end
              if (uri.scheme == 'file' or uri.scheme == nil) and File.exist? uri.path
                  'file'
              elsif uri.class == URI::HTTP and Net::HTTP.new(uri.host,uri.port).get(uri).is_a? Net::HTTPSuccess
                  'remote'
              else
                  raise ArgumentError, "Unreachable URI provided: #{uri.to_s}"
              end
              @uris.push uri
              get_attributes
            }
        end
        
        def duplicate_to dst_dir, file_name = get_default_name
            if dst_dir[/^\..*/]
                dst_dir = File::expand_path dst_dir
            end
            raise ArgumentError, "Path must be absolute (#{dst_dir})" unless dst_dir[/^\//]
            target_uri = URI::parse "file:#{dst_dir}/#{file_name}"
            synchronize {
              return true if get_local_uris.include? target_uri
              if uri = get_local_uris.first and not uri.nil?
                  raise Errno::EEXIST, "File #{File::basename target_uri.path} already exist!" if File.exist? target_uri.path
                  begin
                      FileUtils::link uri.path, target_uri.path
                  rescue Errno::EXDEV => e
                      FileUtils::cp uri.path, target_uri.path
                  end
              else
                  get_remote_uris.each { |remote_uri|
                  begin
                      raise Errno::EEXIST, "File #{File::basename target_uri.path} already exist!" if File.exist? target_uri.path
                      response = Net::HTTP.new(remote_uri.host,remote_uri.port).get(remote_uri)
                      if response.is_a? Net::HTTPSuccess
                          File.open(target_uri.path, "w+") { |f|
                              f.write response.body
                          }
                      else
                          next
                      end
                      #check what we write?
                      break
                  rescue Errno::ENETUNREACH, Errno::EHOSTUNREACH, Errno::ECONNREFUSED, URI::InvalidURIError => e
                      next
                  end
                  }
              end
              @uris.push target_uri if File.exist? target_uri.path
              return File.exist? target_uri.path
            }
        end
        
        #Removes all URL's undo provided dir
        def deduplicate_undo dir
            synchronize {
              (get_local_uris_undo dir).each { |uri|
                  FileUtils::rm_f uri.path
                  @uris.delete uri
              }
            }
        end
        
        #Try to expand current package by other source uris
        def join! other_package
          synchronize {
            if same_as? other_package
              @uris += other_package.uris
              @uris.uniq!
              return true
            else
              return false
            end
          }
        end
        
        #Remove each reachable uri
        def destroy!
          synchronize {
            get_local_uris.each { |victim|
                FileUtils::rm_f victim.path
                @uris.delete victim
            }
          }
        end
        
        #Return true if packages has same attributes
        def same_as? other
            other.is_a? RPM::Package and
            @name == other.name and
            @version == other.version and
            @release == other.release and
            @architecture == other.architecture and
            @digests[:sha256] == other.digests[:sha256]
        end
        
        #Return expected RPM Package file name
        def get_default_name
            "#{@name}-#{@version}-#{@release}.#{@architecture}.rpm"
        end
        
        #Return local URI's undo spicified directory
        def get_local_uris_undo dir
            if dir[/^\..*/]
                dir = File::expand_path dir
            end
            unless dir[/.*\/$/]
                dir = dir + '/'
            end
            synchronize {
              get_local_uris.select { |uri| uri.path[/^#{dir}/] }
            }
        end
        
        #Return every local uris
        def get_local_uris
            synchronize { @uris.select { |uri| uri.scheme == nil or uri.scheme == "file" } }
        end
        
        #Return every remote uris
        def get_remote_uris
            synchronize { @uris.select { |uri| uri.scheme != nil and uri.scheme != "file" } }
        end
        
    private
        def get_attributes
            tmp_file_dir = '/tmp/' + SecureRandom.uuid
            tmp_file_name = tmp_file_dir + '/package.rpm'
            FileUtils.mkdir tmp_file_dir
            raise RuntimeError, "Can't get package to determine attributes" unless duplicate_to tmp_file_dir, 'package.rpm'
            @name, @version, @release, @architecture, @size = `rpm -q --queryformat '%{NAME} %{VERSION} %{RELEASE} %{ARCH} %{SIZE}' -p #{tmp_file_name} 2> /dev/null`.split ' '
            if @name.nil? or @version.nil? or @release.nil? or @architecture.nil?
                raise RuntimeError, "Can't parse name from #{tmp_file_name} by rpm -q command"
            end
            raise RuntimeError, "Unexpected file #{tmp_file_name} disappearing!" unless File.file? tmp_file_name
            @file_size = File.size tmp_file_name
            @digests = { :sha1 => Digest::SHA1.hexdigest(File.read tmp_file_name), :sha256 => Digest::SHA256.hexdigest(File.read tmp_file_name) }
        ensure
            deduplicate_undo tmp_file_dir
            FileUtils.rm_rf tmp_file_dir
        end
    end
    
end
