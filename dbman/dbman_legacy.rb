gotgems = false

begin
require 'rubygems' # not all versions need this one
gotgems = true
rescue LoadError
end

require 'sqlite3'

DDL = {
	:target => "CREATE TABLE target (
 	targetid INTEGER PRIMARY KEY,
	name TEXT UNIQUE NOT NULL,
	hijack TEXT,
	executable TEXT NOT NULL )",

	:game => "CREATE TABLE game (\
	gameid INTEGER PRIMARY KEY,\
	title TEXT NOT NULL,\
	setname TEXT,\
	players INT,\
	buttons INT,\
	ctrlmask INT,\
	genre text,\
	subgenre text,\
	platform text,\
	year INT,\
	launch_counter INT,\
	manufacturer TEXT,\
	system text,\
	target INT NOT NULL,\
	ugid INT,\
	FOREIGN KEY (target) REFERENCES target(targetid) )",

	:broken => "CREATE TABLE broken (\
	gameid INTEGER NOT NULL,\
	event DATETIME default current_timestamp,\
	FOREIGN KEY (gameid) REFERENCES game(gameid) )",

	:game_relations => "CREATE TABLE game_relations (\
	series TEXT NOT NULL,\
	gameid INTEGER NOT NULL,\
	FOREIGN KEY(gameid) REFERENCES game(gameid) ) ",

	:target_arguments => "CREATE TABLE target_arguments (\
	id INTEGER PRIMARY KEY AUTOINCREMENT,\
	target INT NOT NULL,\
	game INT,\
	argument TEXT,\
	mode INT,\
	FOREIGN KEY (target) REFERENCES target(targetid),\
	FOREIGN KEY (game) REFERENCES game(gameid)\
)",

	:appl_arcan => "CREATE TABLE appl_arcan (\
	key TEXT,\
	value TEXT)"
}

# debugging hack, Sqlite3 crashes on execute(nil) (SIGSEGV)
class Dql
	def initialize
@dqltbl = {
	:get_gameid_by_title => "SELECT gameid FROM game WHERE title = ?",
	:get_game_by_gameid => "SELECT gameid, title, setname, players, buttons, ctrlmask, genre, subgenre, year, manufacturer, system, target FROM game WHERE gameid=?",
	:get_game_by_title_setname_targetid => "SELECT gameid, title, setname, players, buttons, ctrlmask, genre, subgenre, year, manufacturer, system, target FROM game WHERE title=? AND setname=? AND target = ?",
	:get_game_by_title_exact => "SELECT gameid, title, setname, players, buttons, ctrlmask, genre, subgenre, year, manufacturer, system, target FROM game WHERE title=?",
	:get_game_by_title_wild => "SELECT gameid, title, setname, players, buttons, ctrlmask, genre, subgenre, year, manufacturer, system, target FROM game WHERE title LIKE ?",
	:get_games_by_target => "SELECT gameid FROM game WHERE target = ?",
	:get_games_title => "SELECT title FROM game",
	:get_arg_by_id_mode => "SELECT argument FROM target_arguments WHERE target = ? AND mode = ? AND game = 0",
	:get_target_by_id => "SELECT targetid, name, executable, hijack FROM target WHERE targetid = ?",
	:get_target_by_name => "SELECT targetid, name, executable, hijack FROM target WHERE name = ?",
	:get_target_ids => "SELECT name, executable FROM target",

	:update_game => "UPDATE game SET setname=?, players=?, buttons=?, ctrlmask=?, genre=?, subgenre=?, year=?, manufacturer=?, system=? WHERE gameid=?",
	:update_target_by_targetid => "UPDATE target SET name = ?, executable = ?, hijack = ? WHERE targetid = ?",
	:insert_game => "INSERT INTO game (title, setname, players, buttons, ctrlmask, genre, subgenre, year, manufacturer, system, target, launch_counter) VALUES (?,?,?,?,?,?,?,?,?,?,?,0)",
	:insert_target => "INSERT INTO target (name, executable, hijack) VALUES (?,?,?)",
	:insert_arg => "INSERT INTO target_arguments (target, game, argument, mode) VALUES (?, ?, ?, ?)",
	:get_games_by_targetid => "select gameid FROM game WHERE target = ?",
	:associate_game => "INSERT INTO game_relations (series, gameid) VALUES (?, ?)",
	:deassociate_game => "DELETE FROM game_relations WHERE gameid = ?",

	:delete_game_by_gameid => "DELETE FROM game WHERE gameid = ?",
	:delete_games_by_targetid => "DELETE FROM game WHERE target = ?",
	:delete_arg_by_gameid_mode => "DELETE FROM target_arguments WHERE game = ? AND mode = ?",
	:delete_arg_by_gameid => "DELETE FROM target_arguments WHERE game = ?",
	:delete_arg_by_targetid => "DELETE FROM target_arguments WHERE target = ?",
	:delete_target_by_id => "DELETE FROM target WHERE targetid = ?"}
	end

	def [](key)
		res = @dqltbl[key]
		if res == nil
				nmex = NameError.new("unknown query requested, #{key}")
				raise nmex
		end

		res
	end
end

DQL = Dql.new

# Wrapped for getting a minimalistic query trace
module DBWrapper
	def execute(qry, *args)
#		STDOUT.print("should execute: #{qry}\n")
#		args.each{|arg| STDOUT.print("\t#{arg}\n") }
		super(qry, args)
	end
end

class DBObject
	@@dbconn = nil

	def DBObject.openDB(o)
		@@dbconn = o
		@@dbconn.extend DBWrapper
		@@dbconn.execute("PRAGMA synchronous = OFF")
	end

end

class Game < DBObject
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

	def store
		qry = ""

		last = nil
		if (@pkid > 0)
			@@dbconn.execute(DQL[:update_game],
				last = [@setname, @players, @buttons, @ctrlmask,
					@genre, @subgenre, @year,
					@manufacturer, @system, @pkid])
		else
			@@dbconn.execute(DQL[:insert_game],
				last = [@title, @setname, @players, @buttons, @ctrlmask,
					@genre, @subgenre, @year,
					@manufacturer, @system, @target.pkid])

			@pkid = @@dbconn.last_insert_row_id()
		end

		if (@family != nil)
			@@dbconn.execute(DQL[:deassociate_game], @pkid)
			@@dbconn.execute(DQL[:associate_game], @family, @pkid)
		end

		@@dbconn.execute(DQL[:delete_arg_by_gameid], @pkid)
		3.times{|arggrp|
			@arguments[arggrp].each{|gamearg|
				@@dbconn.execute(DQL[:insert_arg],
					[ @target.pkid, @pkid, gamearg, arggrp ])
			}
		}
	rescue => er
		STDOUT.print "[Sqlite3 DB] store failed #{er}\n\t #{er.backtrace.join("\n\t")}\n"
		if (last)
			last.each{|val| STDOUT.print(" (#{val.class}) ")}
			STDOUT.print("\n")
		end
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

	def drop_args(mode)
		if (@pkid > 0)
			@@dbconn.execute(DQL[:delete_arg_by_gameid_mode], @pkid, mode)
			true
		else
			false
		end
	end

	def delete
		if (@pkid > 0)
			@@dbconn.execute(DQL[:delete_game_by_gameid], @pkid)
			@@dbconn.execute(DQL[:delete_arg_by_gameid], @pkid)
			true
		else
			false
		end
	end

	def to_s
		"(#{@pkid}) #{title} => #{@target}"
	end

	def execstr(internal, targetpath, rompath)
		resstr = "#{targetpath}/#{@target.target}"
# got game arguments override?

		arglist = @arguments[0] + @arguments[ internal ? 1 : 2 ]

		if (arglist.size == 0)
			arglist = @target.arguments[0] + @target.arguments[ internal ? 1 : 2 ]
		end

		repl = false

		while ( ind = arglist.index("[romset]") )
			arglist[ind] = @setname
			repl = true
		end

		while ( ind = arglist.index("[romsetfull]") )
			arglist[ind] = "#{rompath}#{@setname}"
			repl = true
		end

		arglist.each{|arg| resstr << " #{arg}" }

		resstr << " #{@setname}" unless repl

		resstr
	end

	def Game.Delete( title )
		games = Game.Load(0, title)
		games.each{|game| game.delete }
		games.size
	end

	def Game.FromRow(row)
		newg = Game.new
		newg.pkid    = row[0]
		newg.title   = row[1]
		newg.setname = row[2]
		newg.players = row[3].to_i
		newg.buttons = row[4].to_i
		newg.ctrlmask = row[5].to_i
		newg.genre   = row[6]
		newg.subgenre= row[7]
		newg.year    = row[8].to_i
		newg.manufacturer = row[9]
		newg.system = row[10]
		newg.target  = row[11].to_i
		newg.target  = Target.Load( newg.target, nil )
		newg
	end

	def Game.LoadSingle(title, setname, target)
		dbres = nil

		if (setname == nil) then
			dbres = @@dbconn.execute(DQL[:get_game_by_title_exact], title)
		else
			dbres = @@dbconn.execute(DQL[:get_game_by_title_setname_targetid], title, setname, target)
		end

		dbres.count > 0 ? Game.FromRow(dbres[0]) : nil
	end

	def Game.All(targetid)
		dbres = @@dbconn.execute(DQL[:get_games_by_targetid], targetid).each{|row|
			yield Game.Load(row[0].to_i)[0]
		}
	end

	def Game.Load(gameid, match = nil)
		res = []
		dbres = nil

		if (gameid > 0)
			dbres = @@dbconn.execute(DQL[:get_game_by_gameid], gameid)
		elsif (match)
			match = match.sub("*", "%")
			if (match.count("%") > 0)
				dbres = @@dbconn.execute(DQL[:get_game_by_title_wild], match)
			else
				dbres = @@dbconn.execute(DQL[:get_game_by_title_exact], match)
			end
		else
			return res
		end

		dbres.each{|row| res << Game.FromRow(row) }

		res
	end
end

class Target < DBObject
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

