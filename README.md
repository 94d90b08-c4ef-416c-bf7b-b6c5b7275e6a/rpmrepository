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
But some code in test may be not a best practices
For example, to determine includes repository particular package or use `repository.contains? package` - not `repository.get_packages_list.each {|pkg| pkg.same_as? package ...}`  

**Other advices:**  
1. Resuse `RPM::Package` objects if possible  
If you create two `RPM::Package` with the same URL and `destroy!` one, second package become invalid and throw `RuntimeError` at next access  
Instead, use `correct_package = repository.assimilate side_created_package`  
So, try to accumulate your package objects inside the repository to do not use stand-alone objects  

Structure description
---------------------
There are some classes, that represent entities related to RPM

### Class description
#### Repository
Local RPM (YUM) repository with RPM Packages  
Repository support high-level actions: package addition/deletion/searching e.g. by pattern  
Repository object try to do not (use repodata) but store some related metadata: cached package list, baseurl, name, etc  
Repository (opposite from *createrepo* utility) save metadata type between rebuilds  
Repository try to reuse packages and made to support such behaviour  
It can `assimilate` side package to expand it sources with own  
Also it try to do not re-create packages that adds to repository bu re-use objects.

#### Package
Single abstract RPM Package  
It has some attributes, may be available locally or remote  
May has many source URIs  
It may be duplicated in local directory after creation with http uri  
With such abstract model it can be: created with some source uri than duplicated undo repository  
Try to re-use package objects.  
It means that you should not store package arrays.  
But create it, add to repository, that use added object or re-get similar package from repository by `get_packages_list_by` or so on  

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
- suppose 2 RPM::Package has similar local source(s) URI(s). One is destroyed. Than other raise RuntimeError each time accessed
