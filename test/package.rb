#!/usr/bin/ruby
require 'minitest/spec'
require 'minitest/autorun'
require 'fileutils'

puts "Loading testing environment"
require_relative 'env'

describe 'RPM Package' do
    
    before do
        @remote_uri = REMOTE_URIS.sample
        @package_file_name = File::basename @remote_uri
        @package = RPM::Package.new @remote_uri
    end
    
    it 'should not be createble with wrong URI' do
        wrong_uri = 'hey! i am wrong uri'
        unavailable_uri = 'http://example.org/example.rpm'
        unavailable_file_uri = 'file:///123/123/123/prg.rpm'
        
        -> { RPM::Package.new wrong_uri }.must_raise URI::InvalidURIError
        -> { RPM::Package.new unavailable_uri }.must_raise *[Errno::ENETUNREACH, ArgumentError]
        -> { RPM::Package.new unavailable_file_uri }.must_raise ArgumentError
    end
    
    it 'should be duplicatable' do
        (@package.duplicate_to '.').must_equal true
        (File.exist? @package_file_name).must_equal true
        (@package.duplicate_to '.').must_equal true
    end
    
    it 'should has default name' do
        @package.get_default_name.must_equal @package_file_name
    end
    
    it 'should has file_size attribute' do
        @package.file_size.must_be_instance_of Fixnum
    end
    
    it 'should has sha1 and sha256 digests' do
      @package.digests.must_be_instance_of Hash
      @package.digests.keys.must_equal [:sha1, :sha256]
    end
    
    it 'should be the same' do
        (@package.same_as? RPM::Package.new @remote_uri).must_equal true
        (@package.same_as? RPM::Package.new (REMOTE_URIS - [@remote_uri]).sample).must_equal false
        (@package.same_as? @remote_uri).must_equal false
    end
    
    describe 'join tests' do
        before do
          (@package.duplicate_to '.').must_equal true
          @origin_uris_count = @package.uris.count
          @package_copy = RPM::Package.new @remote_uri
          FileUtils.cp @package.get_local_uris.first.path, "/tmp/package2.rpm"
          @package2 = RPM::Package.new '/tmp/package2.rpm'
          @alien_remote_uri = (REMOTE_URIS - [@remote_uri]).sample
          @alien_package = RPM::Package.new @alien_remote_uri
        end
        
        it 'should not join alien package' do
          (@package.join! @alien_package).must_equal false
          @package.uris.count.must_equal @origin_uris_count
        end
        
        it 'should join duplicated package without changes' do
          (@package.join! @package_copy).must_equal true
          @package.uris.count.must_equal @origin_uris_count
        end
        
        it 'should join copied package with enlarging uris' do
          (@package.join! @package2).must_equal true
          @package.uris.count.must_equal (@origin_uris_count + 1)
        end
        
        describe 'URI split brain' do
          before do
            @package_copy.join! @package
            @package_copy.destroy!
          end
          
          it 'split self brain if destroy package copy' do
            @package.get_local_uris.count.must_equal 1
            (File.exist? @package.get_local_uris.first.path).must_equal true
          end
          
          it 'should raise error on access splitted package' do
            -> {@package.get_local_uris}.must_raise RuntimeError
            -> {@package.get_local_uris_undo '/1/2/3'}.must_raise RuntimeError
            -> {@package.destroy!}.must_raise RuntimeError
            -> {@package.duplicate_to '/1/2/3'}.must_raise RuntimeError
          end
          describe 'workaround' do
              it 'should be reparable' do
                begin
                    @package.get_remote_uris #should raise
                rescue RuntimeError => e
                    (@package.repair!).must_equal true
                end
              end
              it 'should be repairable without splitted brain' do
                prev_uris_count = @package_copy.uris.count
                @package_copy.repair!.must_equal true
                prev_uris_count.must_equal @package_copy.uris.count
              end
          end
          
          after do
            @package_copy.duplicate_to '.'
          end
        end
        
        after do
          @package.deduplicate_undo '.'
          FileUtils.rm_f '/tmp/package2.rpm'
        end
    end
    
    describe 'destructive tests' do
        before do
            @directories = [ './', './tmp', './tmp/2', './tmp2/' ]
            @directories.each { |dir|
                FileUtils::mkdir_p dir
                (@package.duplicate_to dir).must_equal true
            }
            @valid_urls = [
                @package.get_remote_uris.sample,
                @package.get_remote_uris.sample.to_s,
                @package.get_local_uris.sample,
                @package.get_local_uris.sample.path,
                @package.get_local_uris.sample.to_s,
                'file:' + @package.get_local_uris.sample.path,
                ]
        end
        
        it 'should be creatable by valid URIs' do
            @valid_urls.each { |url|
                RPM::Package.new(url).must_be_instance_of RPM::Package
            }
        end
        
        it 'should deduplicate only under specified directory' do
            @package.deduplicate_undo './tmp'
            (File.exist? @package_file_name).must_equal                 true
            (File.exist? './tmp/' + @package_file_name).must_equal      false
            (File.exist? './tmp/2/' + @package_file_name).must_equal    false
            (File.exist? './tmp2/' + @package_file_name).must_equal     true
        end
        
        it 'should be destroyable' do
            @package.destroy!
            (File.exist? @package_file_name).must_equal                 false
            (File.exist? './tmp/' + @package_file_name).must_equal      false
            (File.exist? './tmp/2/' + @package_file_name).must_equal    false
            (File.exist? './tmp2/' + @package_file_name).must_equal     false
        end
        
        after do
            FileUtils::rm_rf './tmp'
            FileUtils::rm_rf './tmp2'
        end
    end
    
    after do
        FileUtils::rm_f @package_file_name
    end
end
