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
[os,tty,vm,fs,colors] = [require('os'), require('tty'), require('vm'), require('fs'), require('./colors')]
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
		@history = []


		process.on 'uncaughtException', (err) -> @displayError err
		
		@outlog = fs.openSync process.env.HOME + "/coffeesh.outlog", 'a+', '644'
		@inlog = fs.openSync process.env.HOME + "/coffeesh.inlog", 'a+', '644'
		@errlog = fs.openSync process.env.HOME + "/coffeesh.errlog", 'a+', '644'
		@debuglog = fs.openSync process.env.HOME + "/coffeesh.debuglog", 'a+', '644'
		
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
		
	displaylogs: ->
		for log in ['coffeesh.outlog', 'coffeesh.inlog', 'coffeesh.errlog', 'coffeesh.debuglog']
			shl.execute("gnome-terminal -t #{log} -e 'tail -f #{process.env.HOME}/#{log}'")
		(null)

	init: ->
		# load history
		fs.open @HISTORY_FILE, 'a+', '664', (err, fd) =>
			return @displayError ["Cannot open history file '#{@HISTORY_FILE}' for writing", err] if err
			@history_fd = fd

		fs.readFile @HISTORY_FILE, 'utf-8', (err, data) =>
			lines = data.split("\r\n")

			lines = lines[..@HISTORY_SIZE]
			lines.reverse().shift()
			@displayDebug lines
			@history = @history.concat lines
			@displayDebug @history
		
		#Load binaries and built-in shell commands
		@binaries = {}
		for pathname in (process.env.PATH.split ':') when path.existsSync(pathname) 
			@binaries[file] = pathname for file in fs.readdirSync(pathname)
			
		@builtin = 
			pwd: =>
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
					@cwd = '~'+newcwd.substr(@home.length)
				else @cwd = newcwd
				#@displayOutput "new directory: #{@cwd}"
			log: (val) =>
				@displayOutput val
			kill: (pid, signal = "SIGTERM") -> 
				process.kill pid, signal
			which: (val) =>
				if @builtin[val]? then console.log 'built-in shell command'.green 
				else if @binaries[val]? then console.log "#{@binaries[val]}/#{val}".white
				else console.log "command '#{val}' not found".red

		root.aliases = @ALIASES
		root.binaries = @binaries
		root.builtin = @builtin
		root.log = @builtin.log
		root.displaylogs = shl.displaylogs
		
		@resetInternals()

		# connect to tty
		@resume()
		
		@ttymgr()

		Fiber(=> 
			@cwd = @execute("/bin/pwd -L")
			@builtin.cd(@cwd)
		).run()
	
		@drawShell()

				
	
	resetInternals: ->
		# internal variables
		@historyIndex = -1
		[@mousex, @mousey] = [0,0]
		@cx = @cy = 0
		@cTabs = [0]
		@cLines = ['']

	resume: ->
		@resetInternals()
		@input.setEncoding('utf8')
		
		@_data_listener = (s) =>
			if (s.indexOf("\u001b[M") is 0) then @keypress s
		@input.on("data", @_data_listener)
		
		@input.on("keypress", (s, key) =>
			@keypress s, key
		).resume()
		tty.setRawMode true
		@mouseTracking on
		return

	pause: ->
		@resetInternals()
		@output.clearLine 0
		@input.removeAllListeners 'keypress'
		@input.removeListener 'data', @_data_listener
		@mouseTracking off
		tty.setRawMode false
		@input.pause()
		
		return 

	close: ->
		@mouseTracking off
		tty.setRawMode false
		@input.destroy()
		return

	runline: ->		
		
		code = @cLines.join("\n")
		
		@resetInternals()

		@displayInput code
		
		
		@history.unshift code
		@history.pop() if @history.length > @HISTORY_SIZE
		fs.write @history_fd, code+"\r\n" if @history_fd?

				
		rcode = Recode code
		@displayDebug("Recoded: #{rcode}\n")
		
		try
			Fiber(=>
				_ = global._
				returnValue = coffee.eval "_=(#{rcode}\n)"
				if returnValue is undefined
					global._ = _
				else
					@displayOutput returnValue
			).run()
		catch err
			@displayError err
	
	
	# Run command non interactively
	execute: (cmd) ->
		fiber = Fiber.current
		lastcmd = ''
		proc = spawn '/bin/sh', ["-c", "#{cmd}"]
		
		proc.stdout.on 'data', (data) =>
			lastcmd = data.toString().trim()
						
		proc.stderr.on 'data', (data) =>
			@displayError data.toString().trim()
			
		proc.on 'exit', (exitcode, signal) =>
			fiber.run()
		yield()
		return lastcmd
	
# Run command interactively	
	run: (cmd) ->
		fiber = Fiber.current
		@pause()
		@output.clearLine 0
		@output.cursorTo 0
		cmdargs = ["-ic", "#{cmd}"]
		proc = spawn '/bin/sh', cmdargs, {cwd: process.cwd(), env: process.env, customFds: [0,1,2]}
		proc.on 'exit', (exitcode, signal) =>
			@input.removeAllListeners 'keypress'
			@input.removeListener 'data', @_data_listener
			@mouseTracking off
			@resume()
			fiber.run()
		yield()
		return

root.shl = new CoffeeShell()

extend root.shl, require('./ttymgr')
extend root.shl, require('./tabcomplete')
extend root.shl, require('./keypress')
#
# Need to add asserts before requiring
# For example, if TAB is set to a length of 0, do not allow
extend root.shl, require("./coffeeshrc")
extend root.shl.ALIASES, require('./coffeesh_aliases')

root.shl.init()