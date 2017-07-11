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
              get_attributes uri
              @uris.push uri
            }
        end
        
        def duplicate_to dst_dir
            if dst_dir[/^\..*/]
                dst_dir = File::expand_path dst_dir
            end
            raise ArgumentError, "Path must be absolute (#{dst_dir})" unless dst_dir[/^\//]
            target_uri = URI::parse "file:#{dst_dir}/#{get_default_name}"
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
            @architecture == other.architecture
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
        def get_attributes uri
            #fix that rpm command supports only file:///1/2/3 not file:/1/2/3
            rpm_uri = uri.dup
            if rpm_uri.scheme == nil or uri.host == nil
                rpm_uri.host = ''
                rpm_uri.scheme = 'file'
            end
            @name, @version, @release, @architecture, @size = `rpm -q --queryformat '%{NAME} %{VERSION} %{RELEASE} %{ARCH} %{SIZE}' -p #{rpm_uri.to_s} 2> /dev/null`.split ' '
            if @name.nil? or @version.nil? or @release.nil? or @architecture.nil?
                raise RuntimeError, "Can't parse name from #{rpm_uri.to_s} by rpm -q command"
            end
            #calc RPM package file size
            if uri.scheme == 'file' or uri.scheme == nil
                raise RuntimeError, "Unexpected file #{uri.to_s} disappearing!" unless File.file? uri.path
                @file_size = File.size uri.path
            else
                response = Net::HTTP.new(uri.host,uri.port).get(uri)
                if response.is_a? Net::HTTPSuccess
                    @file_size = response.body.size
                else
                    raise RuntimeError, "Can't GET #{uri.to_s} for size making"
                end
            end
        end
    end
    
end
