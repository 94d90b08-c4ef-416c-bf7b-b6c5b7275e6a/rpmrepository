#!/usr/bin/env ruby

puts "Require RPM module"
require 'rpm'

puts "Create new repository"
repo = RPM::Repository.new '/tmp/new_repo', 'repo_name'
p repo

puts "It creates repository undo directory /tmp/new_repo"
p Dir.new('/tmp/new_repo').entries

puts "Two package to add:"
pkg1 = RPM::Package.new "http://mirror.centos.org/centos/6/os/x86_64/Packages/NetworkManager-devel-0.8.1-113.el6.i686.rpm"
pkg2 = RPM::Package.new 'http://mirror.centos.org/centos/6/os/x86_64/Packages/GConf2-gtk-2.28.0-7.el6.x86_64.rpm'
p pkg1
p pkg2

puts "Now add them"
p repo.add_packages! [pkg1,pkg2]

puts "It duplicates specified packages into directory"
p pkg1.uris

puts "Try to find package by regular expression"
p repo.get_packages_list_by /^Net/

puts "Then remove it"
p repo.parse_out_packages! /^Net/

puts "Only one package at repository now:"
p repo.get_packages_list

puts "Remove whole repository"
p repo.destroy!

puts "Is repository base_dir exist now?"
p File.directory? '/tmp/new_repo' #false
