use gifnooc

import io/File
import os/Env
import structs/ArrayList

import gifnooc/Entity
import gifnooc/entities/[INI, Fixed]

import reincarnate/[App, Mirrors]

Config: class {
    userFileName: static func -> String {
        version(linux) {
            return "%s/.reincarnate/config" format(Env get("HOME"))
        }
    }

    systemFileName: static func -> String {
        version(linux) {
            return "/etc/reincarnate.conf"
        }
    }

    entity: Entity
    app: App

    init: func (=app) {
        /* create defaults. */
        defaults := FixedEntity new(null)
        _mirrors: MirrorList = MirrorList new()
        _mirrors add("http://meatshop.ooc.eaxeax.de/meat/")
        defaults addValue("Nirvana.APITemplate", "http://nirvana.ooc-lang.org/api%s") \
                .addValue("Nirvana.UsefileTemplate", "http://nirvana.ooc-lang.org%s") \
                .addValue("Nirvana.User", "") \
                .addValue("Nirvana.Token", "") \
                .addValue("Meatshop.Mirrors", _mirrors) \
                .addValue("Meatshop.SuperMirror", "http://meatshop.ooc.eaxeax.de") \
                .addValue("Meatshop.RelativeFilenameScheme", "/%s/%s/%s") \
                .addValue("Meatshop.SuperMirrorSubmit", "%s/submit")
        if(Env get("OOC_LIBS")) {
            defaults addValue("Paths.oocLibs", File new(Env get("OOC_LIBS")))
        } else {
            version(linux) {
                defaults addValue("Paths.oocLibs", File new("/usr/lib/ooc"))
            }
        }
        version(linux) {
            defaults addValue("Paths.Temp", File new("/var/tmp/ooc")) \
                    .addValue("Paths.Yard", File new("%s/.reincarnate/yard" format(Env get("HOME"))))
        }
        top := defaults
        /* system-wide configuration? */
        if(File new(systemFileName()) exists()) {
            top = INIEntity new(top, systemFileName())
        }
        /* user-wide configuration? */
        if(File new(userFileName()) exists()) {
            top = INIEntity new(top, userFileName())
        }
        /* and set it. */
        entity = top
        /* create directories. now. */
        createDirectories()
    }

    /** create all directories mentioned in the configuration if they don't already exist. */
    createDirectories: func {
        file := null as File
        paths := ["Paths.oocLibs", "Paths.Yard", "Paths.Temp"] as ArrayList<String>
        for(path: String in paths) {
            file = get(path, File)
            if(!file exists())
                file mkdirs()
        }
    }

    get: func <T> (path: String, T: Class) -> T {
        entity getOption(path, T)
    }
}
