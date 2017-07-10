#!/usr/bin/env ruby

puts "Require RPM module"
require 'rpm'

puts "Create one package by String uri"
pkg1 = RPM::Package.new ("http://mirror.centos.org/centos/6/os/x86_64/Packages/NetworkManager-devel-0.8.1-113.el6.i686.rpm")
p pkg1
puts "Or by URI"
require 'uri'
pkg2 = RPM::Package.new URI("http://mirror.centos.org/centos/6/os/x86_64/Packages/NetworkManager-devel-0.8.1-113.el6.i686.rpm")
p pkg2
puts "Is it different objects?"
p pkg1 == pkg2 #false

puts  "But the same packages?"
p pkg1.same_as? pkg2 #true

puts "Print default file name - may not actual file name"
p pkg1.get_default_name

puts "Get this file to local machine"
p pkg1.duplicate_to '.'

puts "Now we have this package locally:"
p Dir.new('.').entries

puts "And it has two URI"
p pkg1.uris

puts "And we can remove it:"
p pkg1.deduplicate_undo '.'

puts "Now it disappears"
p Dir.new('.').entries
p pkg1.uris
