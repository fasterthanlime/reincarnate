use deadlogger

import io/[File, FileReader, FileWriter]
import structs/[ArrayList, HashMap]

import deadlogger/[Log, Handler, Formatter]

import reincarnate/[Config, Dependencies, FileSystem, Mirrors, Net, Nirvana, Usefile, Package, Version]
import reincarnate/stage1/[Stage1, Local, Nirvana, URL]
import reincarnate/stage2/[Stage2, Archive, Meatshop, Git]

_setupLogger: func {
    console := StdoutHandler new()
    console setFormatter(ColoredFormatter new(NiceFormatter new()))
    Log root attachHandler(console)
}

_setupLogger()

logger := Log getLogger("reincarnate.App")

App: class {
    config: Config
    net: Net
    mirrors: Mirrors
    nirvana: Nirvana
    fileSystem: FileSystem
    stages1: HashMap<Stage1>
    stages2: HashMap<Stage2>

    init: func {
        /* initialize attributes. */
        config = Config new(this)
        net = Net new(this)
        fileSystem = FileSystem new(this)
        mirrors = Mirrors new(this)
        stages1 = HashMap<Stage1> new()
        stages2 = HashMap<Stage2> new()
        nirvana = Nirvana new(this)
        /* fill stages. */
        /* stage 1 */
        addStage1("local", LocalS1 new(this))
        addStage1("nirvana", NirvanaS1 new(this))
        addStage1("url", URLS1 new(this))
        /* stage 2 */
        addStage2("archive", ArchiveS2 new(this))
        addStage2("git", GitS2 new(this))
        addStage2("meatshop", MeatshopS2 new(this))
    }

    addStage1: func (nickname: String, stage: Stage1) {
        stages1[nickname] = stage
    }

    addStage2: func (nickname: String, stage: Stage2) {
        stages2[nickname] = stage
    }

    /** try to get the usefile described by `location` somehow. */
    doStage1: func (location: String) -> Usefile {
        /* does `location` contain a version? */
        ver := null
        if(location contains('=')) {
            ver = Version fromLocation(location)
            location = location substring(0, location indexOf('='))
        }
        nickname := "nirvana"
        /* i KNOW it's dirty! */
        if(location contains("://")) {
            /* remote stage 1 */
            nickname = "url"
        } else if(location contains(".use")) {
            /* local stage 1 */
            nickname = "local"
        }
        logger debug("Doing stage 1 nickname '%s' on '%s', version '%s'." format(nickname, location, ver))
        usefile := stages1[nickname] getUsefile(location, ver)
        usefile put("_Stage1", nickname) .put("_Location", location)
        usefile
    }

    /** create a `Package` object using the usefile `usefile` somehow. */
    doStage2: func (usefile: Usefile) -> Package {
        /* get the `Origin` option which describes the location of the sourcecode. */
        origin := usefile get("Origin")
        usefile dump() println()
        if(origin == null) {
            Exception new(This, "`Origin` of '%s' is null. Can't do stage 2." format(usefile get("_Slug"))) throw()
        }
        scheme := Net getScheme(origin)
        nickname := "archive"
        if(scheme == "git") {
            /* git repo! */
            nickname = "git"
        } else if(scheme == "meatshop") {
            /* meatshop! */
            nickname = "meatshop"
        }
        logger debug("Doing stage 2 nickname '%s' on '%s'." format(nickname, usefile get("_Slug")))
        usefile put("_Stage2", nickname)
        stages2[nickname] getPackage(usefile)
    }

    _getYardPath: func ~usefile (usefile: Usefile) -> File {
        return _getYardPath(usefile get("_Slug"), usefile get("Version"))
    }

    _getYardPath: func ~slug (slug: String, ver: Version) -> File {
        yard := config get("Paths.Yard", File)
        return yard getChild("%s-%s.use" format(slug, ver))
    }

    _getYardPath: func ~latest (slug: String) -> File {
        ver := null as Version
        if(slug contains('=')) {
            /* slug contains a version! */
            ver = Version fromLocation(slug)
            slug = slug substring(0, slug indexOf('='))
        }
        if(ver == null)
            ver = getLatestInstalledVersion(slug)
        return _getYardPath(slug, ver)
    }

    getInstalledVersions: func (slug: String) -> ArrayList<Version> {
        yard := config get("Paths.Yard", File)
        versions := ArrayList<String> new()
        slugLength := slug length()
        for(child: File in yard getChildren()) {
            if(child name() startsWith(slug + "-")) {
                name := child name()
                versions add(name substring(slugLength + 1, name length() - 4) as Version) /* - ".use" */
            }
        }
        return versions
    }

    getLatestInstalledVersion: func (slug: String) -> Version {
        getLatestVersionOf(getInstalledVersions(slug))
    }

    getLatestVersionOf: static func (versions: ArrayList<Version>) -> Version {
        latest := null as Version
        for(ver: Version in versions) {
            if(latest == null || ver isGreater(latest))
                latest = ver
        }
        return latest
    }

    /** find a version of `requirement slug` (in the "nirvana" stage1.) that 
      * meets `requirement` and return the greatest. If there is none, return null. 
      */
    findVersion: func (requirement: Requirement) -> Version {
        versions := nirvana getVersions(requirement slug)
        meeting := ArrayList<Version> new()
        if(versions != null) {
            for(ver: Version in versions) {
                if(requirement meets(ver)) {
                    meeting add(ver)
                }
            }
            return getLatestVersionOf(meeting)
        }
        return null
    }

    /** store this usefile in the yaaaaaaaaaard. */
    dumpUsefile: func (usefile: Usefile) {
        path := _getYardPath(usefile) path
        logger debug("Storing usefile in the yard at '%s'." format(path))
        writer := FileWriter new(path)
        writer write(usefile dump())
        writer close()
    }

    /* get the usefile from the yard. */
    getUsefile: func (slug: String) -> Usefile {
        reader := FileReader new(_getYardPath(slug))
        usefile := Usefile new(reader)
        reader close()
        usefile
    }

    /** remove the usefile from the yard. */
    removeUsefile: func (usefile: Usefile) {
        path := _getYardPath(usefile)
        if(path remove() == 0) {
            logger debug("Removed usefile from the yard at '%s'." format(path path))
        } else {
            logger warn("Couldn't remove the usefile at '%s'." format(path path))
        }
    }

    keep: func (name: String) {
        logger info("Keeping package '%s'" format(name))
        usefile := getUsefile(name)
        usefile put("_Keep", "yes")
        dumpUsefile(usefile)
    }

    unkeep: func (name: String) {
        logger info("Unkeeping package '%s'" format(name))
        usefile := getUsefile(name)
        usefile remove("_Keep")
        dumpUsefile(usefile)
    }
       
    /** install the package described by `location`: do stage 1, do stage 2, install. */
    install: func ~usefile (location: String) {
        logger info("Installing package '%s'" format(location))
        usefile := doStage1(location)
        package := doStage2(usefile)
        install(package)
    }

    install: func ~package (package: Package) {
        /* resolve dependencies. */
        resolveDependencies(package)
        libDir := package install()
        package usefile put("_LibDir", libDir getAbsolutePath())
        dumpUsefile(package usefile)
        logger info("Installation of '%s' done." format(package usefile get("Name")))
    }

    resolveDependencies: func (package: Package) {
        if(package usefile get("Requires") != null) {
            /* has requirements. */
            reqs := Requirements new(this)
            reqs parseString(package usefile get("Requires"))
            logger debug("Resolving dependencies ...")
            for(loc: String in reqs getDependencyLocations()) {
                logger info("Installing %s as dependency." format(loc))
                this install(loc)
            }
        }
    }

    /** remove the package described by `name`: get the usefile from the yard, stage 2 and ready. */
    remove: func (name: String) {
        /* look for the usefile in the subdir of the oocLibs directory. */
        logger info("Removing package '%s'" format(name))
        usefile := getUsefile(name)
        package := doStage2(usefile)
        remove(package)
    }

    remove: func ~package (package: Package) {
        if(package usefile get("_Keep") != null) {
            logger warn("Version %s has the keepflag set." format(package usefile get("Version")))
            return
        }
        libDir := File new(package usefile get("_LibDir"))
        package remove(libDir)
        removeUsefile(package usefile)
        logger info("Removal of '%s' done." format(package usefile get("_Slug")))
    }

    /** update the package described by `name`: get the usefile, do stage 2 and call `update` */
    /* TODO: do it cooler. */
    update: func (name: String) {
        /* look for the usefile in the subdir of the oocLibs directory. */
        logger info("Updating package '%s'" format(name))
        usefile := getUsefile(name)
        stage1 := stages1[usefile get("_Stage1")]
        hasUpdates := stage1 hasUpdates(usefile get("_Location"), usefile) /* stupid workaround. TODO. */
        if(hasUpdates) {
            logger info("Updates for '%s'!" format(name))
            /* has updates! update me, baby! */
            package := doStage2(usefile)
            libDir := File new(usefile get("_LibDir"))
            /* get the new usefile. */
            newUsefile := stage1 getUsefile(usefile get("_Location"), null)
            package update(libDir, newUsefile)
        } else {
            logger info("Couldn't find updates for '%s'" format(name))
        }
    }

    /** return a list of installed packages. **/
    getPackages: func -> ArrayList<Package> {
        ret := ArrayList<Package> new()
        yard := config get("Paths.Yard", File)
        for(name: String in yard getChildrenNames()) {
            if(name endsWith(".use")) {
                reader := FileReader new(yard getChild(name))
                usefile := Usefile new(reader)
                ret add(doStage2(usefile))
                reader close()
            }
        }
        return ret
    }

    /** return a list of package locations. **/
    getPackageLocations: func -> ArrayList<String> {
        ret := ArrayList<String> new()
        for(package: Package in getPackages()) {
            ret add(package getLocation())
        }
        return ret
    }

    /** submit the usefile to nirvana */
    submit: func ~withString (path, archiveFile: String) {
        reader := FileReader new(path)
        usefile := Usefile new(reader)
        reader close()
        slug: String
        fileSystem splitExt(File new(path) name(), slug&, null)
        submit(slug, usefile, archiveFile)
    }

    submit: func ~withUsefile (slug: String, usefile: Usefile, archiveFile: String) {
        /* TODO: check if archiveFile exists. */
        nirvana submitUsefile(slug, "" /* TODO */, usefile, true /* TODO */)
        /* do we have an archive? if yes, submit it, too */
        if(archiveFile != null)
            mirrors submitPackage(slug, usefile get("Version"), archiveFile)
    }
}

