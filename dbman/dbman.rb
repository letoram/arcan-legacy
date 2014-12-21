#!/usr/bin/ruby
#
#
# dbman dbfile command command_args
# where command:
#  convert dbnamn
#  map targetpath datapath
#
# additional arguments:
# dbtool_path
#

require './dbman_legacy'

def convert(indb, outdb, dbtool = "./arcan_db")
	db = SQLite3::Database.new(indb)
	DBObject.openDB(db)

	Target.All{|tgtname|
		tgt = Target.Load(0, tgtname)

		if (tgt.arguments[2].size > 0)
		end

		if (tgt.arguments[0].size > 0)
		end

# 1. add internal target under name
# 2. foreach game, add configuration

		Game.All(tgt.pkid){|gamename|
		}
		#		p tgt.name
#		p tgt.target
#		p tgt.pkid
#		p tgt.hijack
		}

rescue => er
p er
end

def map(indb, targetp, datap, opts)
	if (targetp == nil or targetp.length == 0 or
			datap == nil or datap.length == 0) then
		show_help();
		return
	end

	tgtptn = opts[tgtptn] && opts[tgtptn][0] ?

	Dir["#{targetp}/*"].each{|tgt|
		Dir["#{datap}/#{tgt}/*"].each{|cfg|
			p cfg
		}
	}
end

def show_help()
	STDOUT.print("DBMan - arcan_db tool support script\n\
Usage:\n\
\tdbman dbfile command [command specific arguments]\n\
Commands:\n\
\tconvert indb      - Converts the contents of a arcan_romman legacy database,\n\
\t                    preserving metadata and target/config arguments.\n\n\
\tmap tgt cfg       - Take a targetpath (tgt) and a Configpath (cfg) with optional\n\
\t                    globbing pattern and map each entry in (targetpath/*) with\n\
\t                    (config/each_target_entry/*).\n\
\t -t,--tgtptn ptn  - Use [ptn] for globbing targets instead of *.\n\
\t -c,--cfgptn ptn  - Use [ptn] for globbing configurations instead of *.\n\
\t -e,--heuristic   - Use built-in heuristics to determine target binary format.\n\
\t                    including possible preload- hijack libraries.\n\
\t -l,--libpath dir - Use [dir] for hijack- libraries (with -e).\n\
                      These will be described relative to SYS_LIBS namespace.\n\
\t -T,--tgtspace nm - Express filepaths for targets relative a specific namespace\n\
\t                    rather than absolute paths.\n\
\t -C,--cfgspace nm - Express filepaths for config file relative a specific namespace\n\
\t                    rather than absolute paths.\n\
supported namespaces:
\tABSOLUTE (default), APPL, APPL_SHARED, SYS_BIN.\n")
end

genopts = [
	[ '--tgtspace',  '-t', GetoptLong::REQUIRED_ARGUMENT ],
	[ '--tgtptn',    '-c', GetoptLong::REQUIRED_ARGUMENT ],
	[ '--cfgptn',    '-e', GetoptLong::REQUIRED_ARGUMENT ],
	[ '--heuristic', '-l', GetoptLong::NO_ARGUMENT       ],
	[ '--libpath',   '-l', GetoptLong::REQUIRED_ARGUMENT ],
	[ '--tgtspace',  '-T', GetoptLong::REQUIRED_ARGUMENT ],
	[ '--cfgspace',  '-C', GetoptLong::REQUIRED_ARGUMENT ]
]

dbfn = ARGV[0]
command = ARGV[1]

opttbl = []

if (dbfn == nil or command == nil) then
	show_help()
	exit
end

case command.downcase
	when "convert" then
		convert(ARGV[2], dbfn)

	when "map" then
		opttbl = {}

		if ARGV[4] != nil then
			GetoptLong.new(*genopts).each{|opt, arg|
				addarg = arg ? arg : opt
				unless(opttbl[opt])
					opttbl[opt] = {}
				end

				opttbl[opt] << addarg
			}
		end
		map(dbfn, ARGV[2], ARGV[3], opttbl)

else
	show_help()
end
