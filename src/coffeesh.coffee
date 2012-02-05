#
## Coffeescript Shell
#
# Load Dependencies
{helpers:{starts,ends,compact,count,merge,extend,flatten,del,last}} = coffee = require 'coffee-script'
{inspect,print,format,puts,debug,log,isArray,isRegExp,isDate,isError} = util = require 'util'
{EventEmitter} = require('events')
{dirname,basename,extname,exists,existsSync} = path = require('path')
{spawn,fork,exec,execFile} = require('child_process')
{Recode} = require './recode'
[os,tty,vm,fs,colors] = [require('os'), require('tty'), require('vm'), require('fs'), require('colors')]
require 'fibers'




class CoffeeShell
	constructor: ->
		# STDIO
		@input = process.stdin
		@output = process.stdout		
		@stderr = process.stderr
		@user = process.env.USER
		@home = process.env.HOME
		@cwd = ''
		process.on 'uncaughtException', -> @error
		
		#@MOUSETRACK = "\x1b[?1003h\x1b[?1005h"
		#@MOUSEUNTRACK = "\x1b[?1003l\x1b[?1005l"
		@HOSTNAME = os.hostname()
		@HISTORY_FILE = process.env.HOME + '/.coffee_history'
		@HISTORY_FILE_SIZE = 1000 # TODO: implement this
		@HISTORY_SIZE = 300
		
		@TABSTOP = 2
		@ALIASES = 
			ls: 'ls -atr --color=auto'
			l: 'ls --color=auto'
			grep: 'grep --color=auto'
			egrep: 'egrep --color=auto'
			fgrep: 'fgrep --color=auto'
		
		
	init: ->
		# load history
		# TODO: make loading history async so no hang on big files
		@history_fd = fs.openSync @HISTORY_FILE, 'a+', '644'
		@history = fs.readFileSync(@HISTORY_FILE, 'utf-8').split("\r\n").reverse()
		@history.shift()
		@resetInternals()
		process.on "SIGWINCH", => 
			[@_columns, @_rows] = @output.getWindowSize()
		
		#Load binaries and built-in shell commands
		@binaries = {}
		for pathname in (process.env.PATH.split ':') when path.existsSync(pathname) 
			@binaries[file] = pathname for file in fs.readdirSync(pathname)

		@builtin = 
			pwd: () =>
				@cwd
			cd: (to) => 
				if to.indexOf('~') is 0
					to = @home + to.substr(1)
				newcwd = @cwd
				if newcwd.indexOf('~') is 0
					newcwd = @home + newcwd.substr(1)
				newcwd = path.resolve newcwd, to
				return if not path.existsSync(newcwd)?
				process.chdir newcwd
				process.env.PWD = newcwd
				if newcwd.indexOf(@home) is 0
					@cwd =	'~'+newcwd.substr(@home.length)
				else @cwd = newcwd
				@_prompt = @PROMPT()
				@output.cursorTo 0
				@output.clearLine 0
				@output.write @_prompt
				@output.cursorTo @_prompt.stripColors.length + @_cursor.x
			echo: (vals...) ->
				for v in vals
					print inspect(v, true, 5, true) + "\n"
				return
			kill: (pid, signal = "SIGTERM") -> 
				process.kill pid, signal
			which: (val) =>
				if @builtin[val]? then console.log 'built-in shell command'.green 
				else if @binaries[val]? then console.log "#{@binaries[val]}/#{val}".white
				else console.log "command '#{val}' not found".red

		root.aliases = @ALIASES
		root.binaries = @binaries
		root.builtin = @builtin
		root.echo = @builtin.echo
		
		Fiber(=> @cwd = @run("/bin/pwd -L"); @builtin.cd(@cwd)).run()

		# connect to tty
		@resume()
		@_prompt = @PROMPT()
		@output.cursorTo 0
		@output.clearLine 0
		@output.write @_prompt
		@output.cursorTo @_prompt.stripColors.length + @_cursor.x
	
	resetInternals: () ->
		# internal variables
		@_historyIndex = -1
		@_cursor = x:0, y:0
		@_mouse = x:0, y:0
		
		@_lines = []
		@_tabs = []
		@_completions = []
		@_lines[@_cursor.y] = ''
		@_tabs[@_cursor.y] = 0
		@PROMPT = => 
			return ("#{@HOSTNAME.white}:#{@cwd.blue.bold} #{if @user is 'root' then "➜".red else "➜".green}  ") if @_cursor.y is 0 and @_lines.length is 1 and @_tabs[0] is 0
			p = "➜ ".green
			for i in [0...@_tabs[@_cursor.y]]
				p+='|'.grey
				p+='·'.grey for j in [0...@TABSTOP]
			(p)
		
		@_prompt = @PROMPT()
		@_consecutive_tabs = 0
		[@_columns, @_rows] = @output.getWindowSize()

	error: (err) -> 
		process.stderr.write (err.stack or err.toString()) + '\n'

	resume: ->
		@resetInternals()
		@input.setEncoding('utf8')
		
		#@_data_listener = (s) =>
		#	if (s.indexOf("\u001b[M") is 0) then @keypress s
		#@input.on("data", @_data_listener)
		
		@input.on("keypress", (s, key) =>
			@keypress s, key
		).resume()
		tty.setRawMode true
		#@output.write @MOUSETRACK
		return

	pause: ->
		@resetInternals()
		@output.clearLine 0
		@input.removeAllListeners 'keypress'
		#@input.removeListener 'data', @_data_listener
		#@output.write @MOUSEUNTRACK
		tty.setRawMode false
		@input.pause()
		
		return 

	close: ->
		#@output.write "\r\n#{@MOUSEUNTRACK}"
		tty.setRawMode false
		@input.destroy()
		return
				
	insertString: (s) ->
	
		s = s.toString("utf-8") if Buffer.isBuffer(s)
		beg = @_lines[@_cursor.y][0...@_cursor.x]
		end = @_lines[@_cursor.y][@_cursor.x...@_lines[@_cursor.y].length]
		@_lines[@_cursor.y] = beg + s + end
		@_cursor.x += s.length
		
		@output.cursorTo 0
		@output.clearLine 0
		@output.write @_prompt + @_lines[@_cursor.y]
		@output.cursorTo @_prompt.stripColors.length + @_cursor.x
		
	runline: ->
		@output.write "\r\n"
		#for i in [0...@_lines.length-1]
		#	@output.cursorTo 0
		#	@output.clearLine 0
		#	@output.moveCursor 0,-1
		#@output.cursorTo 0
		#@output.clearLine 0
		
			
		if @_lines.length is 1 and @_lines[0] is ''
			@resetInternals()
			@_prompt =  @PROMPT()
			@output.write @_prompt
			@output.cursorTo @_prompt.stripColors.length
			return
		
		lines = []
		for i in [0...@_lines.length]
			tabs = ''
			tabs += "\t" for j in [0...@_tabs[i]]
			
			lines[i] = tabs + @_lines[i]
			console.log @_tabs[i], tabs, lines[i]
		code = lines.join("\n")
		console.log code
		@resetInternals()
		
		@history.unshift code
		@history.pop() if @history.length > @HISTORY_SIZE
		fs.write @history_fd, code+"\r\n"
		
		rcode = Recode code
		echo "Recoded: #{rcode}"
		
		try
			Fiber(=>
				_ = global._
				returnValue = coffee.eval "_=(#{rcode}\n)"
				if returnValue is undefined
					global._ = _
				else
					echo returnValue
				@resetInternals()
				@_prompt =  @PROMPT()
				@output.clearLine 0
				@output.cursorTo 0
				@output.write @_prompt
				@output.cursorTo @_prompt.stripColors.length + @_cursor.x
			).run()
		catch err
			@error err
	
	run: (cmd) ->
		fiber = Fiber.current
		@resetInternals()
		
		lastcmd = ''
		proc = spawn '/bin/sh', ["-c", "#{cmd}"]
		proc.stdout.on 'data', (data) =>
			lastcmd = data.toString().trim()
			console.log data.toString()
		proc.stderr.on 'data', (data) =>
			console.log data
		proc.on 'exit', (exitcode, signal) =>
			fiber.run()
		yield()
		return lastcmd
		
	execute: (cmd) ->
		fiber = Fiber.current
		@pause()
		@output.clearLine 0
		@output.cursorTo 0
		@output.write("···\n")
		cmdargs = ["-ic", "#{cmd}"]
		proc = spawn '/bin/sh', cmdargs, {cwd: process.cwd(), env: process.env, customFds: [0,1,2]}
		proc.on 'exit', (exitcode, signal) =>
			@input.removeAllListeners 'keypress'
			#@input.removeListener 'data', @_data_listener
			#@output.write(@MOUSEUNTRACK)
			fiber.run()
			@resume()
		yield()
		return

root.shl = new CoffeeShell()

extend root.shl, require('./tabcomplete')
extend root.shl, require('./keypress')

extend root.shl, require("./coffeeshrc")
extend root.shl.ALIASES, require('./coffeesh_aliases')

root.shl.init()