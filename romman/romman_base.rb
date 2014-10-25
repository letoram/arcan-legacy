gotgems = false

begin
	require 'rubygems' # not all versions need this one
	gotgems = true
rescue LoadError 
end

begin
	dep = "nokogiri"
	require 'nokogiri'
rescue LoadError => ex
	STDOUT.print( " Fatal: The dependency '#{dep}' is missing, install #{gotgems ? "using 'gem install #{dep}'" : 'manually'}. \n")
	exit(1)
end

require 'getoptlong'

ROMMAN_VERSION = 0.4

class GameOutput
	def initialize(o)
		@file_out
	end

	def <<(a)
		
	end
end

class Game
	attr_accessor :pkid, :title, :setname, :players, :buttons, :ctrlmask, :genre,
	:subgenre, :year, :manufacturer, :system, :target, :arguments, :family

	INPUTMASK_LUT = ["joy2way", "doublejoy2way", "joy4way", "doublejoy4way", 
	"joy8way", "doublejoy8way", "dial", "paddle", "stick", "lightgun",
	"keypad", "keyboard", "vjoy2way", "vdoublejoy2way", "trackball", "pedal"]

	def initialize
		@pkid = 0
		@title = ""
		@setname = ""
		@players = 0
		@buttons = 0
		@ctrlmask = 0
		@genre = ""
		@subgenre = ""
		@year = 0
		@manufacturer = ""
		@target = nil
		@system = ""
		@family = nil 
		@arguments = [ [], [], [] ]
	end

	def mask_str( mask = nil)
		mask = mask || @ctrlmask
		label = ""
		
		INPUTMASK_LUT.each_with_index{|val, ind|
			if (mask & (1 << ind) > 0) then
				label << "#{val}, "
			end
		}

		label = label.size > 0 ? label[0..-3] : "no mask"
	end

	def get_mask( label )
		ind = INPUTMASK_LUT.find_index{|a| a == label} 
		if (ind == nil)
			STDOUT.print("Unknown input type: #{label}\n")
			0
		else
			1 << ind
		end
	end

	def to_s
		"(#{@pkid}) #{title} => #{@target}"
	end
end

class Target
	attr_accessor :pkid, :target, :name, :hijack
	attr_reader :arguments

	def initialize
		@pkid = 0
		@target = ""
		@name = ""
		@hijack = nil
		@arguments = [ [], [], [] ]
	end

	def arguments=(o)
		raise NameError.new if o == nil
		@arguments = o	
	rescue => bt
		p bt.backtrace
		exit
	end

	def store_args
		@@dbconn.execute(DQL[:delete_arg_by_targetid], @pkid)

		3.times{|modev|
			@arguments[modev].each{|arg|
				@@dbconn.execute(DQL[:insert_arg], [@pkid, 0, arg, modev])
			}
		}
	end

	def store
		@@dbconn.execute(DQL[:update_target_by_targetid], [@name, @target, @pkid, @hijack])
		store_args()
		
	rescue => dberr
		STDOUT.print("Target(#{@target})::store -- database error, #{dberr}\n")
	end

	def to_s
		@name
	end

	def Target.Create(name, executable, arguments, hijack = nil)
		@@dbconn.execute(DQL[:insert_target], [name, executable, hijack])
		
		res = Target.new
		res.pkid = @@dbconn.last_insert_row_id
		res.name = name
		res.target = executable

		if (arguments)
			res.arguments = arguments
			res.store_args
		end

		res
	end

# Delete all games associated with a target,
# then all arguments, and lastly the target itself.
	def Target.Delete(name)
		target = Target.Load(0, name)

		if (target)
			@@dbconn.execute(DQL[:delete_games_by_targetid], target.pkid)
			@@dbconn.execute(DQL[:delete_arg_by_targetid], target.pkid)
			@@dbconn.execute(DQL[:delete_target_by_id], target.pkid)
			true
		else
			false
		end
	end

	def Target.All
		res = @@dbconn.execute(DQL[:get_target_ids]).each{|row|
			yield row[0].to_s
		}
	end
	
	def Target.Load(pkid, name = nil)
		dbres = nil

		if (pkid > 0)
			dbres = @@dbconn.execute(DQL[:get_target_by_id], [pkid])
		elsif (name != nil)
			dbres = @@dbconn.execute(DQL[:get_target_by_name], [name])
		end

		return nil if (dbres == nil or dbres.size == 0)

		res = Target.new
		res.pkid = dbres[0][0].to_i
		res.name =  dbres[0][1]
		res.target = dbres[0][2]
		res.hijack = dbres[0][3]
		
		3.times{|modev|
			@@dbconn.execute(DQL[:get_arg_by_id_mode], [res.pkid, modev] ).each{|row|
				res.arguments[modev] << row[0]
			}
		}

		res
	end
	private :initialize
end

module Importers
	@@required_symbols = [
		:set_defaults,
		:accepted_arguments,
		:usage,
		:check_target,
		:check_games
	]
	
	def Importers.Each_importer()
		@@instances.each_pair{|key, value| yield value}
	end

	def Importers.Find( name )
		found_cl = Object::constants.find{|b| 
			b.to_s.casecmp(name) == 0
		}

		if (found_cl)
			if (@@instances[found_cl] == nil)
				@@instances[found_cl] = Kernel.const_get( found_cl).new
			end
			
			@@instances[found_cl]
 		else
			nil
		end
	end

	def Importers.Load(path)
		@@instances = {}
		Dir["#{path}/importers/*.rb"].each{|imp|
			modname = imp[imp.rindex('/')+1..-4]
			begin
				load imp
				Importers.Find( modname )
			rescue => er
				STDOUT.print("Fatal: error loading (#{imp}), reason: #{er}\n")
				exit(1)
			end
		}
	end
end


# generic DB routines (DDL here)
def reset_db(dbname)
	STDOUT.print("[reset_db] creating a new database as : #{dbname}\n")

	File.delete(dbname) if (File.exists?(dbname))
	db = SQLite3::Database.new(dbname)

	DDL.each_pair{|key, value|
		db.execute( value )
	}

	db.execute("INSERT INTO appl_arcan VALUES('dbversion', 2);");

	db

rescue => er
	STDOUT.print("Couldn't complete request (reset_db), reason: #{er}\n")
end

def getdb(options)
	db = nil
	if (File.exists?(options[:dbname]) == false or options[:resetdb])
		db = reset_db(options[:dbname])
	else
		db = SQLite3::Database.new(options[:dbname])
	end

	DBObject.openDB( db ) ## -- set so the db is accessible for all games / targets

	db
rescue => er
	STDOUT.print("couldn't acquire DB connection, #{er}\n");
end

def add_preset(fn, group, target)
	a = File.open(fn).readlines
	game = nil

	a.each{|line|

		ind = line.index('=')
		next if (ind == nil or ind == 0)
		key = line[0..ind-1]
		val = line[ind+1..-1].strip!

		if key.upcase == "ENTRY" then
			begin
				if (game != nil) then
					STDOUT.print("[#{group}.cfg], storing entry: #{game.title}\n")
					game.store
				end
			rescue
				STDERR.print("#{group}.cfg : couldn't store #{game}\n")
			end

			game = Game.LoadSingle(val, nil, target.pkid)
			if (not game) then
				game = Game.new
			end

			game.title = val
			game.target = target

		elsif game == nil then
			STDERR.print("#{group}.descr : key without matching entry, ignoring.\n")
	
		elsif game.respond_to?("#{key}=") == false then
			STDERR.print("unknown key (#{key}) specified, ignoring.\n")
		
		else
			begin
				game.send("#{key}=", val)
			rescue
				STDERR.print("error trying to set #{key} to #{val}, ignoring.\n")
			end
		end	
	}	

	if (game != nil) then
		STDOUT.print("[#{group}.descr], storing entry: #{game.title}\n")
		game.store
	end

rescue => er
	STDERR.print("#{group}.descr : parsing error (#{er})\n")
end

def import_roms(options)
# either let the user specify (multiple scanpath arguments)
# or just glob the entire gamesfolder
	if (options[:scangroup])
		groups = []
		options[:scangroup].each{|group|
			path = "#{options[:rompath]}/#{group}"
			
			if File.exists?(path)
				groups << group
			else
				STDOUT.print("[builddb] Specified group path (#{path}) doesn't exist, ignored.\n")
			end
		}
	else
		groups = []
		Dir[ "#{options[:rompath]}/*" ].each{|entry|
			entry.slice!( "#{options[:rompath]}/" )
			if (entry == "system") then
				STDOUT.print("skipping 'system' group\n")
			else
				groups << entry
				STDOUT.print("adding group \t#{entry} for scanning\n")
			end
		}
	end

	db = getdb(options)
	
	
# for each path (group) to scan, check if it's on the skiplist
# else sweep importers for one that accepts it, and (as an optional fallback)
# use the generic one. The importer will yield a number of Game instances
# as it consumes the group members
	groups.each{|group|
		if (options[:skipgroup][group] or group.upcase == "SYSTEM")
			STDOUT.print("\tIgnoring #{group}\n" )
			next
		end

		imp = Importers.Find(group)
		imp = Importers.Find("generic") if (imp == nil and options[:generic])

		if (imp == nil)
			STDOUT.print("No importer found for #{group}, ignoring.\n")
			next
		end

		begin	
		unless (imp.check_target(group, options[:targetpath]))
			STDOUT.print("#{imp.to_s} Couldn't open target: #{group}, ignoring.\n")
			next
		end
		rescue
			STDOUT.print("#{imp.to_s} Importer failed, moving on.\n")
			next 
		end
	
		fn = "#{options[:rompath]}/#{group}/#{group}.descr"
		if (File.exists?(fn)) 
			add_preset(fn, group, imp.target)
			next
		end

		STDOUT.print("#{imp.to_s} processing\n")
		imp.check_games( "#{options[:rompath]}/#{group}"){|game|
			game.store
			STDOUT.print("\t|--> Added : #{game.title}\n")
		}

		STDOUT.print("#{imp.to_s} processed\n")
	}
end

def list(options)

	gametitle = ""
	db = getdb(options)

	if (options[:gamesbrief])
		db.execute(DQL[:get_games_title]).each{|row|
			STDOUT.print("#{row}\n")
		}
	end

	if (options[:targets])
		Target.All{|target|
			STDOUT.print("#{target}\n")
		}
	end
	
	if (options[:showgame])
		gametitle = options[:showgame]

		if gametitle.count('*') > 0
			gametitle = gametitle.sub('*', '%')
		end

		Game.Load(0, gametitle).each{|game|
			STDOUT.print("Title: #{game.title}\n\
			ID:#{game.pkid}\n\
			Setname: #{game.setname}\n\
			Players: #{game.players}\n\
			Buttons: #{game.buttons}\n\
			Controllers: #{game.mask_str}\n\
			Genre / Subgenre: #{game.genre}#{game.subgenre and game.subgenre.size > 0? "/" : ""}#{game.subgenre}\n\
			Manufactured: #{game.manufacturer} (#{game.year})\n\
			Target: #{game.target.name}\n")
		}
	end
	
rescue => er
	STDOUT.print("Couldn't list games, possible database issue: #{er}, #{er.backtrace}\n")
end

def addgame(args)

	if (args.size < 3)
		STDERR.print("alterdb --addgame failed, the command needs at least three arguments (title, target, setname).\n")
		return false
	end

	a = Game.Load(0, args[0])
	if (a.size != 0)
		STDERR.print("alterdb --addgame failed, the game #{args[0]} already exists.\n")
		return false
	end
	
	tgt = Target.Load(0, args[1])
	if (tgt == nil)
		STDERR.print("alterdb --addgame failed, the target #{args[1]} does not exist.\n")
		return false
	end
	
	newgame = Game.new
	newgame.title = args[0]
	newgame.target = tgt
	newgame.setname = args[2]
	
	args[3..-1].each{|subarg|
		kvary = subarg.split(/\=/)
		if (kvary.size != 2)
			STDERR.print("alterdb --addgame, couldn't decode optarg (#{subarg}), ignored.\n")
			next
		else
			begin
				case kvary[0] 
					when "players"  then newgame.players  = kvary[1].to_i
					when "buttons"  then newgame.buttons  = kvary[1].to_i
					when "ctrlmask" then newgame.ctrlmask = kvary[1].to_i
					when "genre"    then newgame.genre    = kvary[1].to_s
					when "subgenre" then newgame.subgenre = kvary[1].to_s
					when "year"     then newgame.year     = kvary[1].to_i
					when "manufacturer" then newgame.manufacturer = kvary[1].to_i
					when "system" then newgame.system = kvary[1].to_s
				else
					STDERR.print("alterdb --addgame, unknown optarg (#{kvary[0]}), ignored.")
				end
			rescue
				STDERR.print("alterdb --addgame, error decoding optarg (#{kvary[0]} => #{kvary[1]}, ignored.)")
			end
		end
	}

	newgame.store
end

def alterdb(options)
	options[:resetdb] = false 
	getdb(options)
	gamequeue = {}
	ind = 0

# find or load game if arguments are present
# decode and attach to argument array
# all alter- options are queued in gamequeue and pushed at the end.
	[ options[:gameargs], options[:gameintargs], options[:gameextargs] ].each{| gmeargs|
		if (gmeargs)
			args = argsplit(gmeargs)
			if (args.size <= 1)
				STDERR.print("alterdb, game()(int)(ext)args : missing title and/or arguments, ignored\n.")
			else
			  gamequeue[ args[0] ] = Game.Load(0, args[0]) unless gamequeue[ args[0] ]
			  if (gamequeue[ args[0] ])
				gamequeue[ args[0] ].arguments[ind] = args[1..-1]
			  else
				STDERR.print("alterdb, game()(int)(ext)args : no matching title found, ignored.\n")
  			  end
			end
		end

		ind += 1
	}

	gamequeue.each{|game| game.store }

	if (options[:addgame])
		args = argsplit(options[:addgame])
		addgame(args)
	end
	
	if (options[:addtarget])
		args = argsplit(options[:addtarget])
		if (args.size == 2)
			Target.Create(args[0], args[1], [[],[],[]])
		else
		  STDERR.print("alterdb --addtarget failed, the command needs precisely two arguments (name, executable).\n")
		end
	end

	targetqueue = {}
	ind = 0
	
	# find or load game if arguments are present
	# decode and attach to argument array
	# all alter- options are queued in gamequeue and pushed at the end.
	[ options[:targetargs], options[:targetintargs], options[:targetextargs] ].each{|tgtargs|
		if (tgtargs)
			args = argsplit(tgtargs)
			if (args.size <= 1)
				STDERR.print("alterdb, target()(int)(ext)args : missing name and/or arguments, ignored\n.")
			else
				targetqueue[ args[0] ] = Target.Load(0, args[0]) unless targetqueue[ args[0] ]
				if (targetqueue[ args[0] ])
					targetqueue[ args[0] ].arguments[ind] = args[1..-1]
				else
					STDERR.print("alterdb, target()(int)(ext)args : no matching found, ignored.\n")
				end
			end
		end

	ind += 1
	}
	
	targetqueue.each_pair{|key, tgt| tgt.store }
	
	if (options[:deletetarget] != nil)
		
		if ( Target.Delete(options[:deletetarget]) )
			STDOUT.print("alterdb, --deletetarget, target and corresponding game entries removed.\n")
		else
			STDERR.print("alterdb, --deletetarget, target could not be deleted (not found).\n")
		end
	end
	
	if (options[:deletegame] != nil)
		game = Game.Delete(options[:deletegame])
		STDOUT.print("alterdb, --deletegame (#{options[:deletegame]}), \# #{game} entries removed from database.\n")
	end
end

def execstr(options)
	db = getdb(options)
	if (options[:execgame] == nil)
		STDOUT.print("[Execstr] No game specified.\n")
		return false
	end

	execstr = ""
	games = Game.Load(options[:execgame].to_i, nil)
	if (games.size == 0)
		STDOUT.print("No matching title (#{options[:execgame]})")
	elsif (games.size > 1)
		STDOUT.print("Multiple titles found: \n")
		games.each{|game| STDOUT.print("\t#{game.title}\n") }
	else	
		execstr = games[0].execstr(options[:execmode] == "internal", options[:targetpath], options[:rompath])
	end

	STDOUT.print("#{execstr}\n")

	if (options[:execlaunch])
		STDOUT.print("[Execstr] launching..\n")
		system(execstr)
	end
rescue => er
	STDOUT.print("[Execstr] Couldn't generate execstr: #{er}, #{er.backtrace}\n")
end
