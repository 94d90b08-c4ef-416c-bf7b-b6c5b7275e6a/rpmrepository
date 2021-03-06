#!/usr/bin/env ruby
require 'minitest/spec'
require 'minitest/autorun'
require 'fileutils'
require 'uri'

puts "Loading testing environment"
require_relative 'env'

describe 'RPM Repository creation' do
    
    before do
        @remote_uris = REMOTE_URIS
        @packages = @remote_uris.collect { |uri| RPM::Package.new uri  }
        @base_dir = File::expand_path './tmp'
        @base_dir2 = File::expand_path './tmp2'
    end
    
    it 'should be creatable without base_dir' do
        RPM::Repository.new @base_dir
    end
    
    it 'should be creatable with base_dir' do
        FileUtils::mkdir @base_dir
        RPM::Repository.new @base_dir
    end
    
    describe 'constructive tests' do
        
        before do
            @repository = RPM::Repository.new @base_dir
            @repository2 = RPM::Repository.new @base_dir2
        end
        
        it 'should has different uniq names' do
          (@repository.name == @repository2.name).must_equal false
        end
        
        it 'should has correct attributes' do
            @repository.name.must_be_instance_of String
            -> {@repository.uid}.must_raise Exception
            @repository.base_dir.must_be_instance_of Dir
            @repository.tmp_dir.must_be_instance_of Dir
            @repository.status.must_equal :ok
        end
        
        it 'should has correct layout' do
            File.directory?(@repository.base_dir).must_equal true
            File.directory?(@repository.tmp_dir).must_equal true
            @repository.base_dir.entries.must_include 'Packages'
            @repository.base_dir.entries.must_include 'repodata'
        end
        
        it 'should return local config' do
            @repository.get_local_conf.must_be_instance_of String
        end
        
        it 'should cleanup tmp files' do
            @repository.clean
            @repository.tmp_dir.entries.count.must_equal 0
            @repository.base_dir.entries.count.wont_equal 0
        end
        
        describe 'package addition' do
            
            before do
                @victim = @packages.sample
                @repository.add_package! @victim
                @victim_location = @victim.get_local_uris_undo(@repository.base_dir.path).first
                @victim_copy = RPM::Package.new @victim.uris.sample
            end
            
            it 'should be added to repository' do
                File.file?(@victim_location.path).must_equal true
                (@repository.get_packages_list.include? @victim).must_equal true
            end
            
            it 'should be alone' do
                @repository.get_packages_list.count.must_equal 1
            end
            
            it 'should not be alien' do
                (@repository.contains? @victim).must_equal true
            end
            
            it 'should be in repository' do
                (@repository.send(:get_own, @victim_copy).same_as? @victim).must_equal true
            end
            
            describe 'package assimilation' do
              before do
                @side_package = RPM::Package.new @victim.get_remote_uris.first
                @alien_package = RPM::Package.new (@packages - [@victim]).sample.get_remote_uris.first
                (@repository.contains? @side_package).must_equal true
                (@repository.contains? @alien_package).must_equal false
              end
              
              it 'should assimilate the same' do
                (@repository.assimilate! @side_package).must_equal true
                @side_package.uris.count.must_equal 2
                (@repository.get_packages_list.include? @side_package).must_equal true
                (@repository.get_packages_list.include? @victim).must_equal false
              end
              
              it 'should not assimilate aliens' do
                (@repository.assimilate! @alien_package).must_equal false
                @alien_package.uris.count.must_equal 1
                (@repository.get_packages_list.include? @alien_package).must_equal false
                (@repository.get_packages_list.include? @victim).must_equal true
              end
              
            end
            
            describe 'package deletion' do
                
                before do
                    @repository.remove_package!(@victim_copy).must_equal true
                end
                
                it 'should be removed' do
                    @repository.get_packages_list.must_be_empty
                end
                
            end
            
            describe 'wrong package deletion' do
                
                before do
                    -> {@repository.remove_package 'Absolutely NOT a package URI'}.must_raise Exception
                end
                
                it 'should not remove package' do
                    @repository.get_packages_list.count.must_equal 1
                end
                
            end
            
        end
        
        describe 'packages addition' do
            
            before do
                @repository.add_packages! @packages
                @repo_packages_list = @repository.get_packages_list
            end
            
            it 'should return similar packages' do
                @repository.get_packages_list.must_equal @packages
            end
            
            describe 'dry rebuild' do
                before do
                    @repository.rebuild
                end
                
                it 'anyway should return similar packages' do
                    @repository.get_packages_list.must_equal @packages
                end
            end
            
            it 'should add correct count' do
                @repo_packages_list.count.must_equal @packages.count
            end
            
            it 'should be at repository' do
                @packages.each { |pkg|
                    @repo_packages_list.each { |r_pkg|
                        pkg.get_local_uris_undo(@repository.base_dir.path).first.path.must_equal pkg.uris.last.path
                    }
                }
            end
            
            it 'should be at FS' do
                @packages.each { |pkg|
                    File.file?(pkg.get_local_uris_undo(@repository.base_dir.path).first.path).must_equal true
                }
            end
            
            describe 'package duplication' do
                before do
                    -> {@repository.add_package! @packages.last}.must_raise RuntimeError
                end
                it 'should not be added' do
                    @repository.get_packages_list.count.must_equal @repo_packages_list.count
                end
            end
            
            describe 'packages removal' do
                
                before do
                    @packages_to_remove = @packages[0..2]
                    @packages_remove_rezult = @repository.remove_packages! @packages_to_remove
                    @packages_list_after_removal = @repository.get_packages_list
                end
                
                it 'should contain correct packages count' do
                    @repository.get_packages_list.count.must_equal @packages.count - @packages_to_remove.count
                end
                
                it 'should remove every package' do
                    @packages_remove_rezult[:removed].count.must_equal @packages_to_remove.count
                    @packages_remove_rezult[:skipped].must_be_empty
                end
                
                it 'should save other packages' do
                    permanent_packages_count = 0
                    @repo_packages_list.each { |pkg|
                        @packages_list_after_removal.each { |pkg2|
                            permanent_packages_count+=1 if
                                pkg.object_id == pkg2.object_id
                        }
                    }
                    permanent_packages_count.must_equal @packages[3..-1].count
                end
                
            end
            
            describe 'incorrect packages removal' do
                
                before do
                    @packages_to_remove = @packages[0..2] +
                        ['/a/lot/of', '/incorrect/uris', '/and/one/correct', @packages.first];
                    @packages_remove_rezult = @repository.remove_packages! @packages_to_remove
                end
                
                it { @packages_remove_rezult[:skipped].count.must_equal 3 }
                it { @packages_remove_rezult[:removed].count.must_equal 4 }
                
            end
            
            describe 'parsing out package' do
                
                before do
                    @full_name_pattern = @packages.sample.get_default_name
                    @parsing_out_rezult = @repository.parse_out_packages! @full_name_pattern
                end
                
                it 'should be removed' do
                    @repository.get_packages_list_by(@full_name_pattern).must_be_empty
                    @repository.get_packages_list.count.must_equal @packages.count - 1
                end
                
                it 'should be mentioned at rezult' do
                    File::basename(@parsing_out_rezult[:removed].first.get_default_name).must_equal @full_name_pattern
                end
                
                it 'should not skip any' do
                    @parsing_out_rezult[:skipped].must_be_empty
                end
                
            end
            
            describe 'figure out packages' do
                
                before do
                    @name_pattern = /^#{@packages.sample.get_default_name[0..2]}.*/
                    @assume_match_packages_count = @packages.select{|pkg|pkg.get_default_name[@name_pattern]}.count
                end
                
                it "should found packages" do
                    @repository.get_packages_list_by(@name_pattern).count.must_equal @assume_match_packages_count
                end
                
                describe 'parsing out finded packages' do
                    
                    before do
                        @parsing_out_rezult = @repository.parse_out_packages! @name_pattern
                    end
                    
                    it "should parse packages" do
                        @assume_match_packages_count.must_equal @parsing_out_rezult[:removed].count
                        @parsing_out_rezult[:skipped].must_be_empty
                    end
                    
                    it 'should not remove other packages' do
                        @repository.get_packages_list.count.must_equal @packages.count - @assume_match_packages_count
                    end
                    
                    it 'should not be findable after' do
                        @repository.get_packages_list_by(@name_pattern).must_be_empty
                    end
                    
                end
                
            end
            
        end
        
        describe 'destructive tests' do
            
            before do
              @repository.destroy!
              @repository2.destroy!
            end
            
            it 'should be destroyed' do
                (File.exist? @repository.base_dir).must_equal false
                @repository.status.must_equal :destroyed
                (File.exist? @repository2.base_dir).must_equal false
                @repository2.status.must_equal :destroyed
            end
            
#            it 'should not be usable' do
#            
#            
#            end
            
        end
        
    end
    
    after do
        FileUtils::rm_rf @base_dir
        FileUtils::rm_rf @base_dir2
    end
end
