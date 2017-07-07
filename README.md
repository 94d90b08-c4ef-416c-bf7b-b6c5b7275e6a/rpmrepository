RPM Module
==========
Module provides some functionality to manipulate with RPM packages and repositories  
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
See test scripts for moar  

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
- package  
- repository  
- repofactory  

TODOs
-----
- RepoFactory: check repository names for unique
- package sroup supporting (comps)
- remove repository uid, use name instead
- add repositpory locking
- add parallel tests
- safe destrouyed repository from acts
- rewrite repository interface with strong argument checks
- use contains? + same_as? + (de)duplicate_undo for package-related repository operations
