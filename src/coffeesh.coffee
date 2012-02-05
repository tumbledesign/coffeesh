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

class Shell
	constructor: ->
		# STDIO
		@input = process.stdin
		@output = process.stdout		
		@stderr = process.stderr
		@user = process.env.USER
		@home = process.env.HOME
		@cwd = ''
		process.on 'uncaughtException', -> @error
		
		@MOUSETRACK = "\x1b[?1003h\x1b[?1005h"
		@MOUSEUNTRACK = "\x1b[?1003l\x1b[?1005l"
		@HOSTNAME = os.hostname()
		@HISTORY_FILE = process.env.HOME + '/.coffee_history'
		@HISTORY_FILE_SIZE = 1000 # TODO: implement this
		@HISTORY_SIZE = 300
		@PROMPT_CONTINUATION = => 
			p = "➜ ".green
			for i in [0...@_tabs]
				p += @PROMPT_TAB
			p+=" "
			(p)
				
		@PROMPT_TAB = "··>".blue.bold
		@_tabs = 0
		@PROMPT = => ("#{@HOSTNAME.white}:#{@cwd.blue.bold} #{if @user is 'root' then "➜".red else "➜".green}  ")
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
		@_prompt = @PROMPT()
		@_lines = []
		@_completions = []
		@_lines[@_cursor.y] = ''
		@_tabs = 0
		[@_columns, @_rows] = @output.getWindowSize()

	error: (err) -> 
		process.stderr.write (err.stack or err.toString()) + '\n'

	resume: ->
		@resetInternals()
		@input.setEncoding('utf8')
		@_data_listener = (s) =>
			if (s.indexOf("\u001b[M") is 0) then @write s
		@input.on("data", @_data_listener)
		@input.on("keypress", (s, key) =>
			@write s, key
		).resume()
		tty.setRawMode true
		@output.write @MOUSETRACK
		return

	pause: ->
		@resetInternals()
		@output.clearLine 0
		@input.removeAllListeners 'keypress'
		@input.removeListener 'data', @_data_listener
		@output.write @MOUSEUNTRACK
		tty.setRawMode false
		@input.pause()
		
		return 

	close: ->
		@output.write "\r\n#{@MOUSEUNTRACK}"
		tty.setRawMode false
		@input.destroy()
		return
				
	write: (s, key) ->
		
		#We need to handle mouse events, they are not provided by node's tty.js
		if not key? and (s.indexOf("\u001b[M") is 0)
			modifier = s.charCodeAt(3)
			key ?= shift: !!(modifier & 4), meta: !!(modifier & 8), ctrl: !!(modifier & 16)
			[@_mouse.x, @_mouse.y] = [s.charCodeAt(4) - 33, s.charCodeAt(5) - 33]
			if ((modifier & 96) is 96)
				key.name ?= if modifier & 1 then 'scrolldown' else 'scrollup'
			else if modifier & 64 then key.name ?= 'mousemove'
			else
				switch (modifier & 3)
					when 0 then key.name ?= 'mousedownL'
					when 1 then key.name ?= 'mousedownM'
					when 2 then key.name ?= 'mousedownR'
					when 3 then key.name ?= 'mouseup'
					#else return
			#Disable mouse events for now
			if key.name? then return

		key ?= {}

		# enter
		if s is '\r'
			@runline()
			return
			
		# ctrl enter
		else if s is '\n'
			@output.cursorTo 0
			@output.clearLine 0
			@output.write @_prompt + @_lines[@_cursor.y] + '\n'
			@_cursor.y++
			@_lines[@_cursor.y] = ''
			@_cursor.x = 0
			@_prompt =  @PROMPT_CONTINUATION()
			@output.cursorTo 0
			@output.clearLine 0
			@output.write @_prompt + @_lines[@_cursor.y]
			@output.cursorTo @_prompt.stripColors.length + @_cursor.x
			return
			
		keytoken = [if key.ctrl then "C^"] + [if key.meta then "M^"] + [if key.shift then "S^"] + [if key.name then key.name] + ""

		switch keytoken
			
		## Utility functions

			# SIGINT
			# TODO: fix
			when "C^c"
				@output.write "\r\n"
				@pause()
				@resume()
				@output.cursorTo 0
				@output.clearLine 0
				@output.write @_prompt
				@output.cursorTo @_prompt.stripColors.length + @_cursor.x
				
			# Background
			when "C^z" 
				return process.kill process.pid, "SIGTSTP"
			
			# Logout
			when "C^d"
				@close() if @_cursor.x is 0 and @_lines[@_cursor.y].length is 0 and @_lines.length is 1

			when "tab" 
				if @_cursor.x is 0
					@_cursor.x = 0
					@_tabs++
					@output.cursorTo 0
					@output.clearLine 0
					@_prompt = @PROMPT_CONTINUATION()
					@output.write @_prompt
					@output.cursorTo @_prompt.stripColors.length
				else
					@tabComplete()
			when "S^tab"
				if @_cursor.x is 0
					return if @_tabs is 0
					@_cursor.x = 0
					@_tabs--
					
					@output.cursorTo 0
					@output.clearLine 0
					@_prompt = @PROMPT_CONTINUATION()
					@output.write @_prompt
					@output.cursorTo @_prompt.stripColors.length
				else
					@tabComplete()
			#when "enter" then @runline()

			# Clear line
			when "C^u"
				@_lines[@_cursor.y] = ''
				@_cursor.x = 0
				@output.cursorTo 0
				@output.clearLine 0
				@output.write @_prompt
				@output.cursorTo @_prompt.stripColors.length

		## Deletions

			when "backspace", "C^h"
				#console.log @_cursor.x, @_cursor.y, @_lines.length, (@_cursor.y < @_lines.length)
				if @_cursor.x > 0 and @_lines[@_cursor.y].length > 0
					@_cursor.x--
					@_lines[@_cursor.y] = @_lines[@_cursor.y][0...@_cursor.x] + @_lines[@_cursor.y][@_cursor.x+1..]
					
					@output.clearLine 0
					@output.cursorTo 0
					@output.write @_prompt + @_lines[@_cursor.y]
					@output.cursorTo @_prompt.stripColors.length + @_cursor.x
					
				else if @_cursor.y isnt 0 and @_cursor.y is (+@_lines.length-1) and @_lines[@_cursor.y].length is 0
					@_cursor.y--
					@_lines.pop() unless @_cursor.y is 0
					@_prompt = if @_cursor.y is 0 then @PROMPT() else @PROMPT_CONTINUATION()
					
					#console.log @_cursor.x, @_cursor.y, @_lines
					@_cursor.x = @_lines[@_cursor.y].length
								
					@output.clearLine 0
					@output.moveCursor 0,-1
					@output.cursorTo @_prompt.stripColors.length + @_cursor.x
				else if @_cursor.y is 0 and @_cursor.x is 0  and @_lines[0].length is 0
					@_lines = ['']
						
			when "delete", "C^d"
				if @_cursor.x < @_lines[@_cursor.y].length
					@_cursor.x--
					@_lines[@_cursor.y] = @_lines[@_cursor.y][0...@_cursor.x]
					@output.moveCursor -1
					@output.clearLine 1
					@output.cursorTo @_prompt.stripColors.length + @_cursor.x
					
			# Word left
			when "C^w", "C^backspace", "M^backspace"
				if @_cursor.x > 0
					leading = @_lines[@_cursor.y][0...@_cursor.x]
					match = leading.match(/// \S*\s* $ ///)
					leading = leading[0...(leading.length - match[0].length)]
					@_lines[@_cursor.y] = leading + @_lines[@_cursor.y][@_cursor.x...@_lines[@_cursor.y].length]
					@_cursor.x = leading.length
					@_prompt = if @_cursor.y is 0 then @PROMPT() else @PROMPT_CONTINUATION()
					@output.clearLine 0
					@output.cursorTo 0
					@output.write @_prompt + @_lines[@_cursor.y]
					@output.cursorTo @_prompt.stripColors.length + @_cursor.x
					
				else if @_cursor.y is 0 and @_cursor.x is 0 and @_lines[0].length is 0
					@_lines = ['']
					
					
			# Word right
			when "C^delete", "M^d", "M^delete"
				if @_cursor.x < @_lines[@_cursor.y].length
					trailing = @_lines[@_cursor.y][@_cursor.x...]
					match = trailing.match(/// ^ \s*\S+ ///)
					@_cursor.x = @_lines[@_cursor.y].length - trailing.length
					
					@_lines[@_cursor.y] = @_lines[@_cursor.y][0...@_cursor.x] + trailing[match[0].length...]
					
					@_prompt = if @_cursor.y is 0 then @PROMPT() else @PROMPT_CONTINUATION()
					@output.clearLine 0
					@output.cursorTo 0
					@output.write @_prompt + @_lines[@_cursor.y]
					@output.cursorTo @_prompt.stripColors.length + @_cursor.x
					
					#if @_cursor.y is 0 and @_cursor.x is 0 and @_lines is []
					#	@_lines = ['']
			# Line right
			when "C^k", "C^S^delete"
				@_lines[@_cursor.y] = @_lines[@_cursor.y][0...@_cursor.x]
				@output.clearLine 1
			# Line left
			when "C^S^backspace", "M^S^d"
				@_lines[@_cursor.y] = @_lines[@_cursor.y][@_cursor.x...]
				@_cursor.x = 0
				@output.clearLine 0
				@output.cursorTo 0
				@output.write @_prompt + @_lines[@_cursor.y]
				@output.cursorTo @_prompt.stripColors.length + @_cursor.x
				
		## Cursor Movements

			when "home", "C^a"
				@_cursor.x = 0
				@output.cursorTo @_prompt.stripColors.length + @_cursor.x
			when "end", "C^e"
				@_cursor.x = @_lines[@_cursor.y].length
				@output.cursorTo @_prompt.stripColors.length + @_cursor.x
			when "left", "C^b"
				if @_cursor.x > 0
					@_cursor.x--
					@output.moveCursor -1, 0
			when "right", "C^f"
				unless @_cursor.x is @_lines[@_cursor.y].length
					@_cursor.x++
					@output.moveCursor 1, 0
			# Word left
			when "C^left", "M^b"
				if @_cursor.x > 0
					leading = @_lines[@_cursor.y][0...@_cursor.x]
					match = leading.match(/// \S*\s* $ ///)
					@_cursor.x -= match[0].length
					@output.cursorTo @_prompt.stripColors.length + @_cursor.x
			# Word right
			when "C^right", "M^f"
				if @_cursor.x < @_lines[@_cursor.y].length
					trailing = @_lines[@_cursor.y][@_cursor.x...]
					match = trailing.match(/// ^ \s*\S+ ///)
					@_cursor.x += match[0].length
					@output.cursorTo @_prompt.stripColors.length + @_cursor.x


		## History
			when "up", "C^p", "down", "C^n"
				
				if keytoken in ['up', 'C^p'] and @_cursor.y > 0 and @_cursor.y <= @_lines.length and @_lines.length > 0
					@_cursor.y--
					@output.moveCursor 0, -1
					@_prompt = (if @_cursor.y is 0 then @PROMPT() else @PROMPT_CONTINUATION())
					@_cursor.x = @_lines[@_cursor.y].length
					@output.cursorTo @_prompt.stripColors.length + @_cursor.x
					return
					
				else if keytoken in ['down', 'C^n'] and @_cursor.y < @_lines.length-1 and @_cursor.y >= 0 and @_lines.length > 0
					@_cursor.y++
					@output.moveCursor 0, 1
					@_prompt = (if @_cursor.y is 0 then @PROMPT() else @PROMPT_CONTINUATION())
					@_cursor.x = @_lines[@_cursor.y].length
					@output.cursorTo @_prompt.stripColors.length + @_cursor.x
					return
				
				if @_historyIndex + 1 < @history.length and keytoken in ['up', 'C^p']
					@_historyIndex++
					@output.moveCursor 0, @_lines.length-1
					
				else if @_historyIndex > 0 and keytoken in ['down', 'C^n']
					@_historyIndex--
					
				else if @_historyIndex is 0
					for i in [0...@_lines.length-1]
						@output.cursorTo 0
						@output.clearLine 0
						@output.moveCursor 0,-1
					@output.cursorTo 0
					@output.clearLine 0
					@resetInternals()
					@_prompt = @PROMPT()
					@output.write @_prompt
					@output.cursorTo @_prompt.stripColors.length
					return
				else return
				
				for i in [0...@_lines.length-1]
					@output.cursorTo 0
					@output.clearLine 0
					@output.moveCursor 0,-1

				@_lines = (@history[@_historyIndex]).split('\n')
				@_cursor.y = @_lines.length
				
				for i in [0...@_lines.length]
					@_cursor.y = i
					@_cursor.x = @_lines[@_cursor.y].length
					@_prompt = if @_cursor.y is 0 then @PROMPT() else @PROMPT_CONTINUATION()
					@output.clearLine 0
					@output.cursorTo 0
					@output.write @_prompt
					@output.write @_lines[@_cursor.y]
					@output.write '\n' if i < @_lines.length-1
					@output.cursorTo @_prompt.stripColors.length + @_cursor.x

						
				if keytoken in ['down', 'C^n']
					@_cursor.y = 0
					@output.moveCursor 0, -1*(@_lines.length-1)
					@_prompt = @PROMPT()
					@_cursor.x = @_lines[0].length
					@output.cursorTo @_prompt.stripColors.length + @_cursor.x

		## Mouse stuff
			when 'mousedownL' then
			when 'mousedownM' then
			# Right click is captured by gnome-terminal, but C^rightclick and S^rightclick are available
			when 'C^mousedownR' then
			when 'mouseup' then
			when 'mousemove' then
			when 'scrolldown' then
			when 'scrollup' then

		## Directly output char to terminal
			else
				s = s.toString("utf-8") if Buffer.isBuffer(s)
				beg = @_lines[@_cursor.y][0...@_cursor.x]
				end = @_lines[@_cursor.y][@_cursor.x...@_lines[@_cursor.y].length]
				@_lines[@_cursor.y] = beg + s + end
				@_cursor.x += s.length
				@output.cursorTo 0
				@output.clearLine 0
				@output.write @_prompt + @_lines[@_cursor.y]
				@output.cursorTo @_prompt.stripColors.length + @_cursor.x
#				if s
#					lines = s.split /\r\n|\n|\r/
#					for i,line of lines
#						@runline() if i > 0
#						@insertString lines[i]

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


	tabComplete: ->
		@autocomplete( (@_lines[@_cursor.y][0...@_cursor.x]).split(' ').pop(), ( (completions, completeOn) =>
			if completions and completions.length
				if completions.length is 1
					@insertString completions[0].slice(completeOn.length)
				else
					@output.write "\r\n"
					
					width = completions.reduce((a, b) ->
						(if a.length > b.length then a else b)
					).length + 2
					
					maxColumns = Math.floor(@_columns / width) or 1
					rows = Math.ceil(completions.length / maxColumns)

					completions.sort()

					if rows > @_rows
						@output.write "Do you wish to see all #{completions.length} possibilities? "
						return
					
					for row in [0...rows]
						for col in [0...maxColumns]
							idx = row * maxColumns + col
							break  if idx >= completions.length

							@output.write completions[idx]
							@output.write " " for s in [0...(width-completions[idx].length)] when (col < maxColumns - 1)

						@output.write "\r\n"

					@output.moveCursor @_prompt.stripColors.length + @_cursor.x, -(rows+1)

					#prefix = ""
					min = completions[0] 
					max = completions[completions.length - 1]
					for i in [0...min.length]
						if min[i] isnt max[i]
							prefix = min.slice(0, i)
							break
						prefix = min

					@insertString prefix.slice(completeOn.length) if prefix.length > completeOn.length
			)
		)
							

	## Autocompletion

	# Returns a list of completions, and the completed text.
	autocomplete: (text, cb) ->
		prefix = filePrefix = builtinPrefix = binaryPrefix = accessorPrefix = varPrefix = null
		completions = fileCompletions = builtinCompletions = binaryCompletions = accessorCompletions = varCompletions = []
		
		# Attempt to autocomplete a valid file or directory
		isdir = text[text.length-1] is '/'
		dir = if isdir then text else (path.dirname text) + "/"
		filePrefix = (if isdir then	'' else path.basename text)
		#echo [isdir,dir,filePrefix]
		if path.existsSync dir then listing = (fs.readdirSync dir).filter((e) -> e[0] isnt '.') 
		fileCompletions = []
		for item in listing when item.toLowerCase().indexOf(filePrefix.toLowerCase()) is 0
			fileCompletions.push(if fs.lstatSync(dir + item).isDirectory() then item + "/" else item)
		
		# Attempt to autocomplete a builtin cmd
		builtinPrefix = text
		builtinCompletions = (cmd for own cmd,v of builtin when cmd.toLowerCase().indexOf(builtinPrefix.toLowerCase()) is 0)
		
		# Attempt to autocomplete a valid executable
		binaryPrefix = text
		binaryCompletions = (cmd for own cmd,v of binaries when cmd.toLowerCase().indexOf(binaryPrefix.toLowerCase()) is 0)
		
		# Attempt to autocomplete a chained dotted attribute: `one.two.three`.
		if match = text.match /([\w\.]+)(?:\.(\w*))$/
			[all, obj, accessorPrefix] = match
			try
				val = vm.runInThisContext obj
				accessorCompletions = (el for own el,v of Object(val) when el.toLowerCase().indexOf(accessorPrefix.toLowerCase()) is 0)
			catch error
				accessorCompletions = []
				accessorPrefix = null
			
		# Attempt to autocomplete an in-scope free variable: `one`.
		varPrefix = text.match(/^(?![\/\.])(\w+)$/i)?[1]
		varPrefix = '' if text is ''
		if varPrefix?
			vars = vm.runInThisContext 'Object.getOwnPropertyNames(Object(this))'
			keywords = (r for r in coffee.RESERVED when r[..1] isnt '__')
			possibilities = vars.concat keywords
			varCompletions = (el for el in possibilities when el.toLowerCase().indexOf(varPrefix.toLowerCase()) is 0)
		else varPrefix = null

		# Combine the various types of completions
		prefix = text
		for [c,p] in [[varCompletions, varPrefix], [accessorCompletions, accessorPrefix], [fileCompletions, filePrefix], [binaryCompletions, binaryPrefix], [builtinCompletions, builtinPrefix]]
			if c.length
				completions = completions.concat c
				prefix = p

		#echo [completions, prefix]
		cb(completions, prefix)

	## Eval and Execute
	
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
		
		
			
		code = @_lines.join("\n")
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
		proc.stderr.on 'data', (data) =>
			console.log data.toString()		
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
			@input.removeListener 'data', @_data_listener
			@output.write(@MOUSEUNTRACK)
			fiber.run()
			@resume()
		yield()
		return



extend((root.shl = new Shell()), require("./coffeeshrc"))
extend(root.shl.ALIASES, require('./coffeesh_aliases'))
root.shl.init()