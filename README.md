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

Examples (Usage)
----------------
Look at [examples](examples) directory to know how to use [RPM::Package](examples/package.rb) and [RPM::Repository](examples/repository.rb) classes  
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
Test environment configuration [here](test/env.rb)  
Testing scripts:  
- [package](test/package.rb)  
- [repository](test/repository.rb)  
- [repofactory](test/repofactory.rb)  

TODO aka known issues
---------------------
- package group supporting (comps)
- add repository locking (for other processes)
- add parallel tests
- safe destroyed repository from acts
- add RPM::Repository.assimilate (join package with repositoried one if exist)
- suppose 2 RPM::Package has similar local source(s) URI(s). One is destroyed. What about another?
