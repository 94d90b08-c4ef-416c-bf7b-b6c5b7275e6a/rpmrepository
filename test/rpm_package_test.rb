#!/usr/bin/ruby
require 'minitest/spec'
require 'minitest/autorun'
require 'fileutils'

puts "Loading testing environment"
require_relative 'env_test'

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
    
    it 'should be the same' do
        (@package.same_as? RPM::Package.new @remote_uri).must_equal true
        (@package.same_as? RPM::Package.new (REMOTE_URIS - [@remote_uri]).sample).must_equal false
        (@package.same_as? @remote_uri).must_equal false
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
