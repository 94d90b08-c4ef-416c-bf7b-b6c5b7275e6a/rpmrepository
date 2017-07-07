RPM Module
==========
Module provides some functionality to manipulate with RPM [packages](README.md\#package) and [repositories](README.md\#repository)  
God, forgive us!  

Reason
------
Maybe there are many tools  
But noone deal with server side:  
- how to create repository?  
- manage it (add packages, remove them)?  
- get some metadata (package count, total size, rebuilding history)  
So, here we go ... unfortunately  

Convention
----------
All this made on **CentOS** and for **CentOS**  
Maybe some classes usable without any restrictions  
But other distributives and packagers may not follow convention  

Usage
-----
### Deal with Package
``` ruby
require 'rpm'
pkg1 = RPM::Package.new ("http://mirror.centos.org/centos/6/os/x86_64/Packages/NetworkManager-devel-0.8.1-113.el6.i686.rpm")
#Or like this
require 'uri'
pkg2 = RPM::Package.new URI("http://mirror.centos.org/centos/6/os/x86_64/Packages/NetworkManager-devel-0.8.1-113.el6.i686.rpm")
#This is different objects
p pkg1 == pkg2 #false
#But the same packages
p pkg1.same_as? pkg2 #true
#Print default file name - may not actual file name
p pkg1.get_default_name
#Get this file to local machine
p pkg1.duplicate_to '.'
#Now we have this package locally
p Dir.new('.').entries
#And there are two URI
p pkg1.uris
#And we can remove it
pkg1.deduplicate_undo '.'
#And now it disappears
p Dir.new('.').entries
p pkg1.uris
```
### Deal with Repository
``` ruby
require 'rpm'
#Create new repository
repo = RPM::Repository.new '/tmp/new_repo', 'repo_name'
#It creates repository undo directory /tmp/new_repo
p Dir.new('/tmp/new_repo').entries
#Two package to add
pkg1 = RPM::Package.new "http://mirror.centos.org/centos/6/os/x86_64/Packages/NetworkManager-devel-0.8.1-113.el6.i686.rpm"
pkg2 = RPM::Package.new 'http://mirror.centos.org/centos/6/os/x86_64/Packages/GConf2-gtk-2.28.0-7.el6.x86_64.rpm'
#Now add them
repo.add_packages! [pkg1,pkg2]
#It duplicates specified packages into directory
p pkg1.uris
#Try to find package by regular expression - return URI, not package
p repo.get_package_list_by /^Net/
#Then remove it
p repo.parse_out_pkgs! /^Net/
p repo.get_pkg_list
#Now remove whole repository
repo.destroy!
p File.directory? '/tmp/new_repo' #false
```

See [test scripts](test) for moar  

Structure description
---------------------
There are some classes, that represent entities related to RPM

### Class description
#### Repository
Local RPM (YUM) repository with RPM Packages  
Repository support high-level actions: package addition/deletion/searching e.g. by pattern  
Repository object try to do not (use repodata) but store some related metadata: cached package list, baseurl, name, etc  
Repository (opposite from *createrepo* utility) save metadata type between rebuilds  

#### Package
Single abstract RPM Package  
It has some attributes, may be available locally or remote or not  
May has many source URIs  
It may be duplicated in local directory after creation with http uri  
With such abstract model it can be: created with some source uri than duplicated undo repository  

#### RepoFactory
Synced repository array  
Allow to manage(access,add) group of repositories in parallel  
Wrap over Array of RPM::Repository

Testing
-------
[Minitest](https://github.com/seattlerb/minitest) uses  
Test environment configuration - *test/env_test.rb*  
Each class has own test script like `test/rpm_<entity>_test.rb`  
where *entity* is one of:  
- [package](test/rpm_package_test.rb)  
- [repository](test/rpm_repository_test.rb)  
- [repofactory](test/rpm_repofactory_test.rb)  

TODOs
-----
- package sroup supporting (comps)
- remove repository uid, use name instead
- add repositpory locking
- add parallel tests
- safe destrouyed repository from acts
- rewrite repository interface with strong argument checks
- use contains? + same_as? + (de)duplicate_undo for package-related repository operations
