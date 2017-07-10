#!/usr/bin/env ruby
require 'minitest/spec'
require 'minitest/autorun'
require 'fileutils'
require 'uri'

puts "Loading testing environment"
require_relative 'env_test'

describe 'repository factory' do
    
    before do
        packages = REMOTE_URIS.collect { |uri| RPM::Package.new uri  }
        @main_repo = RPM::Repository.new File::expand_path './tmp/-1'
        @main_repo.add_packages! packages
        @packages = @main_repo.get_packages_list
        @repositories = (0..(5..9).to_a.sample).to_a.collect { |repo_id| 
            repo = RPM::Repository.new File::expand_path "./tmp/#{repo_id}"
            repo.add_packages! @packages.sample (1..3).to_a.sample
            repo.name = repo_id.to_s + 'nd/th repository'
            repo
        }
        @alien_repository = RPM::Repository.new File::expand_path('./tmp/-2'), @repositories[0].name
        @factory = RPM::RepoFactory.new
    end
    
    it 'should not has repositories' do
        @factory.get_repositories.must_be_empty
        @factory.get_repository_by(@repositories.first.name).must_be_nil
    end
    
    describe 'add repositories' do
        
        before do
            @repositories.each {|repo| 
                @factory.add_repository(repo).must_equal true
            }
        end
        
        it 'should add repositories' do
            @factory.get_repositories.count.must_equal @repositories.count
        end
        
        it 'should not add repository with the same name' do
            ->() { @factory.add_repository(@alien_repository) }.must_raise ArgumentError
        end
        
        it 'should has each of repositories' do
            @repositories.each { |repo|
                @factory.get_repository_by(repo.name).must_be_instance_of RPM::Repository
            }
        end
        
        it 'should touch every repository in cycle' do
            i = 0
            @factory.each { |repo|
                @repositories.must_include repo
                i += 1
            }
            i.must_equal @repositories.count
        end
        
        describe 'remove repositories' do
            
            before do
                @count_to_remove = (1..@repositories.count).to_a.sample
                @destroyed_repos = []
                @repositories.sample(@count_to_remove).each { |repo|
                    @factory.destroy_repository_by!(repo.name).must_equal true
                    @destroyed_repos.push repo
                    
                }
            end
            
            it 'should remove spicified count' do
                @factory.get_repositories.count.must_equal @repositories.count - @count_to_remove
            end
            
            it 'should not contain destroyed' do
                @destroyed_repos.each { |repo|
                    @factory.get_repository_by(repo.name).must_be_nil
                }
            end
            
        end
        
    end
    
    after do
        @repositories.each { |repo| 
            repo.destroy!
        }
        @main_repo.destroy!
        @alien_repository.destroy!
    end
    
end
