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
[vm,fs,colors] = [require('vm'), require('fs'), require('colors')]
tty = require('tty')
os = require 'os'
require 'fibers'

#Load binaries and built-in shell commands
binaries = {}
for pathname in (process.env.PATH.split ':') when path.existsSync(pathname) 
	binaries[file] = pathname for file in fs.readdirSync(pathname)

builtin = 
	pwd: -> 
		process.cwd.apply(this,arguments)
	cd: -> 
		process.chdir.apply(this,arguments)
		shl.setPrompt()
		shl.prompt()
	echo: (vals...) ->
		for v in vals
			print inspect(v, true, 5, true) + "\n"
		return
	kill: (pid, signal = "SIGTERM") -> 
		process.kill pid, signal
	which: (val) ->
		if builtin[val]? then console.log 'built-in shell command'.green 
		else if binaries[val]? then console.log "#{binaries[val]}/#{val}".white
		else console.log "command '#{val}'' not found".red

root.binaries = binaries
root.builtin = builtin
root.echo = builtin.echo

class Shell
	constructor: ->
		@HOSTNAME = os.hostname()
		@HISTORY_FILE = process.env.HOME + '/.coffee_history'
		@HISTORY_FILE_SIZE = 1000 # TODO: implement this
		@HISTORY_SIZE = 300
		@PROMPT_CONTINUATION = =>
			('......> '.green)
		@PROMPT = =>
			user = process.env.USER
			cwd = process.cwd()
			user.white + "@#{@HOSTNAME}".white.bold + (if user is "root" then "➜ ".red else "➜ ".blue) + (path.basename(cwd) or "/").cyan.bold + " "
		@ALIASES = 
			ls: 'ls --color=auto'
			l: 'ls -latr --color=auto'
			grep: 'grep --color=auto'
			egrep: 'egrep --color=auto'
			fgrep: 'fgrep --color=auto'
		
		# STDIO
		@input = process.stdin
		@output = process.stdout		
		@stderr = process.stderr
		process.on 'uncaughtException', -> @error
		@mousetrack = on:"\x1b[?1003h\x1b[?1005h", off:"\x1b[?1003l\x1b[?1005l"
		
	init: ->
		# load history
		# TODO: make loading history async so no hang on big files
		@history_fd = fs.openSync @HISTORY_FILE, 'a+', '644'
		@history = fs.readFileSync(@HISTORY_FILE, 'utf-8').split("\r\n").reverse()
		@history.shift()
		@historyIndex = -1
		
		# command aliases
		for alias,val of @ALIASES when not builtin[alias]? and binaries[val.split(' ')[0]]?
			builtin[alias] = (params...) -> 
				shl.execute binaries[val.split(' ')[0]] + '/' + val + " " + params.join(" ")

		# internal variables
		@_cursor = x:0, y:0
		@_mouse = x:0, y:0
		@_prompt = ''
		@_line = ''
		@_code = ''
		@_consecutive_tabs = 0
		[@_columns, @_rows] = @output.getWindowSize()
		process.on "SIGWINCH", => 
			[@_columns, @_rows] = @output.getWindowSize()

		# connect to tty
		@resume()

	error: (err) -> 
		process.stderr.write (err.stack or err.toString()) + '\n'

	resume: ->
		@input.setEncoding('utf8')

		@_data_listener = (s) =>
			if (s.indexOf("\u001b[M") is 0) then @write s
			
		@input.on("data", @_data_listener)
		@input.on("keypress", (s, key) =>
			@write s, key
		).resume()
		tty.setRawMode true
		@output.write @mousetrack.on
		@output.moveCursor -@mousetrack.on.length
		@_cursor.x = 0
		@_line = ''
		@_code = ''
		@setPrompt()
		@prompt()
		return

	pause: ->
		@_cursor.x = 0
		@_line = ''
		@_code = ''
		@output.clearLine 0
		@input.removeAllListeners 'keypress'
		@input.removeListener 'data', @_data_listener
		@output.write @mousetrack.off
		@output.moveCursor -@mousetrack.off.length
		@input.pause()
		tty.setRawMode false
		return 

	close: ->
		@input.removeAllListeners 'keypress'
		@input.removeAllListeners 'data'
		@output.write @mousetrack.off
		@output.moveCursor -@mousetrack.off.length
		tty.setRawMode false
		@input.destroy()
		return

	setPrompt: (p) ->
		p ?= @PROMPT
		@_prompt = p()
			
	prompt: ->
		@_line = ""
		@historyIndex = -1
		@_cursor.x = 0 
		@refreshLine()

	refreshLine: ->
		@output.cursorTo 0
		@output.write @_prompt
		@output.write @_line
		@output.clearLine 1
		@output.cursorTo @_prompt.stripColors.length + @_cursor.x


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

		key ?= {}

		# enter
		if s is '\r'
			@_code += @_line
			@numlines = @_code.split('\n').length-1
			@_cursor.y = @numlines
			@runline()
			return
			
		# ctrl enter
		else if s is '\n'
			@insertString '\n'
			@_code += @_line
			@setPrompt @PROMPT_CONTINUATION
			@prompt()
			return
			
		keytoken = [if key.ctrl then "C^"] + [if key.meta then "M^"] + [if key.shift then "S^"] + [if key.name then key.name] + ""

		if keytoken is "tab" then @_consecutive_tabs++ else @_consecutive_tabs = 0

		
		switch keytoken
			
		## Utility functions

			# SIGINT
			when "C^c"
				console.log()
				@pause()
				@resume()

			# Background
			when "C^z" then	return process.kill process.pid, "SIGTSTP"

			# Logout
			when "C^d"
				@close() if @_cursor.x is 0 and @_line.length is 0

			when "tab" then @tabComplete()
			#when "enter" then @runline()

			# Clear line
			when "C^u"
				@_cursor.x = 0
				@_line = ""
				@refreshLine()

		## Deletions

			when "backspace", "C^h"
				if @_cursor.x > 0 and @_line.length > 0
					@_line = @_line.slice(0, @_cursor.x - 1) + @_line.slice(@_cursor.x, @_line.length)
					@_cursor.x--
					@refreshLine()
				else
					if @_code.length > 0
						code = @_code.split('\n')
						code.pop()
						code.unshift()
						#@_code = code.join('\n')
						@_code = @_line = ''
						for i in [0...code.length]
							@output.clearLine 0
							@output.cursorTo 0
							@output.moveCursor 0,-1
							@output.clearLine 0
							@output.cursorTo 0
							@_cursor.x = code[i].length
							if i is 0
								@setPrompt()
								@_line = code[i] + (if i < code.length-1 then '\n' else '')
								@refreshLine()
							else
								@setPrompt @PROMPT_CONTINUATION
								@_line = code[i] + (if i < code.length-1 then '\n' else '')
								@refreshLine()
							if i < code.length - 1
								@_code += @_line
								@numlines = @_code.split('\n').length-1
								@_cursor.y = @numlines
			when "delete", "C^d"
				if @_cursor.x < @_line.length
					@_line = @_line.slice(0, @_cursor.x) + @_line.slice(@_cursor.x + 1, @_line.length)
					@refreshLine()
			# Word left
			when "C^w", "C^backspace", "M^backspace"
				if @_cursor.x > 0
					leading = @_line.slice(0, @_cursor.x)
					match = leading.match(/([^\w\s]+|\w+|)\s*$/)
					leading = leading.slice(0, leading.length - match[0].length)
					@_line = leading + @_line.slice(@_cursor.x, @_line.length)
					@_cursor.x = leading.length
					@refreshLine()
			# Word right
			when "C^delete", "M^d", "M^delete"
				if @_cursor.x < @_line.length
					trailing = @_line.slice(@_cursor.x)
					match = trailing.match(/^(\s+|\W+|\w+)\s*/)
					@_line = @_line.slice(0, @_cursor.x) + trailing.slice(match[0].length)
					@refreshLine()
			# Line right
			when "C^k", "C^S^delete"
				@_line = @_line.slice(0, @_cursor.x)
				@refreshLine()
			# Line left
			when "C^S^backspace"
				@_line = @_line.slice(@_cursor.x)
				@_cursor.x = 0
				@refreshLine()

		## Cursor Movements

			when "home", "C^a"
				@_cursor.x = 0
				@refreshLine()
			when "end", "C^e"
				@_cursor.x = @_line.length
				@refreshLine()
			when "left", "C^b"
				if @_cursor.x > 0
					@_cursor.x--
					@output.moveCursor -1, 0
			when "right", "C^f"
				unless @_cursor.x is @_line.length
					@_cursor.x++
					@output.moveCursor 1, 0
			# Word left
			when "C^left", "M^b"
				if @_cursor.x > 0
					leading = @_line.slice(0, @_cursor.x)
					match = leading.match(/([^\w\s]+|\w+|)\s*$/)
					@_cursor.x -= match[0].length
					@refreshLine()
			# Word right
			when "C^right", "M^f"
				if @_cursor.x < @_line.length
					trailing = @_line.slice(@_cursor.x)
					match = trailing.match(/^(\s+|\W+|\w+)\s*/)
					@_cursor.x += match[0].length
					@refreshLine()
			when "C^up"
				@output.moveCursor 0, -1
			when "C^down"
				@output.moveCursor 0, 1

		## History
			when "up", "C^p", "down", "C^n"
				if keytoken in ['up', 'C^p'] and @_cursor.y > 0 and @_cursor.y <= @numlines and @numlines > 1
					@_cursor.y--
					@output.moveCursor 0, -1
					return
				else if keytoken in ['down', 'C^n'] and @_cursor.y < @numlines and @_cursor.y >= 0 and @numlines > 1
					@_cursor.y++
					@output.moveCursor 0, 1
					return
				
				
				for i in [0...@numlines]
					@output.cursorTo 0
					@output.clearLine 0
					@output.moveCursor 0,-1
					
				if @historyIndex + 1 < @history.length and keytoken in ['up', 'C^p']
					@historyIndex++
				else if @historyIndex > 0 and keytoken in ['down', 'C^n']
					@historyIndex--
				else if @historyIndex is 0
					@historyIndex = -1
					@_cursor.x = 0
					@_line = ""
					@_code = ""
					@setPrompt()
					@refreshLine()
					return
				else return

				@_line = @_code = ''
				code = @history[@historyIndex]
				lns = code.split('\n')
				@numlines = lns.length-1
				@_cursor.y = @numlines
				
				for i in [0...lns.length]
					@output.clearLine 0
					@output.cursorTo 0
					@_cursor.x = lns[i].length
					if i is 0
						@setPrompt()
						@_line = lns[i] + (if i < lns.length-1 then '\n' else '')
						@refreshLine()
					else
						@setPrompt @PROMPT_CONTINUATION
						@_line = lns[i] + (if i < lns.length-1 then '\n' else '')
						@refreshLine()
					if i < lns.length - 1
						@_code += @_line
						#@numlines = @_code.split('\n').length-1
						#@_cursor.y = @numlines
					#@_line = ''

		## Mouse stuff
			when 'mousedownL' then
			when 'mousedownM' then
			when 'mousedownR' then
			when 'mouseup' then
			when 'mousemove' then
			when 'scrolldown' then
			when 'scrollup' then

		## Directly output char to terminal
			else
				s = s.toString("utf-8") if Buffer.isBuffer(s)
				if s
					lines = s.split /\r\n|\n|\r/
					for i,line of lines
						@runline() if i > 0
						@insertString lines[i]

	insertString: (c) ->
		if @_cursor.x < @_line.length
			beg = @_line.slice(0, @_cursor.x)
			end = @_line.slice(@_cursor.x, @_line.length)
			@_line = beg + c + end
			@_cursor.x += c.length
			@refreshLine()
		else
			@_line += c
			@_cursor.x += c.length
			@output.write c

	tabComplete: ->
		@autocomplete( @_line.slice(0, @_cursor.x).split(' ').pop(), ( (completions, completeOn) =>
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
					
					for row in [0...rows]
						for col in [0...maxColumns]
							idx = row * maxColumns + col
							break  if idx >= completions.length

							@output.write completions[idx]
							@output.write " " for s in [0...(width-completions[idx].length)] when (col < maxColumns - 1)

						@output.write "\r\n"

					@output.write "\r\n"

					@output.moveCursor 0, -(rows+2)

					#prefix = ""
					min = completions[0] 
					max = completions[completions.length - 1]
					for i in [0...min.length]
						if min[i] isnt max[i]
							prefix = min.slice(0, i)
							break
						prefix = min

					@insertString prefix.slice(completeOn.length) if prefix.length > completeOn.length
				
				@refreshLine()
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
		if path.existsSync dir then listing = fs.readdirSync dir
		fileCompletions = []
		for item in listing when item.indexOf(filePrefix) is 0
			fileCompletions.push(if fs.lstatSync(dir + item).isDirectory() then item + "/" else item)
		
		# Attempt to autocomplete a builtin cmd
		builtinPrefix = text
		builtinCompletions = (cmd for own cmd,v of builtin when cmd.indexOf(builtinPrefix) is 0)
		
		# Attempt to autocomplete a valid executable
		binaryPrefix = text
		binaryCompletions = (cmd for own cmd,v of binaries when cmd.indexOf(binaryPrefix) is 0)
		
		# Attempt to autocomplete a chained dotted attribute: `one.two.three`.
		if match = text.match /([\w\.]+)(?:\.(\w*))$/
			[all, obj, accessorPrefix] = match
			try
				val = vm.runInThisContext obj
				accessorCompletions = (el for own el,v of Object(val) when el.indexOf(accessorPrefix) is 0)
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
			varCompletions = (el for el in possibilities when el.indexOf(varPrefix) is 0)
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
		if !@_code.toString().trim()
			@setPrompt()
			@prompt()
			return

		@history.unshift @_code
		@history.pop() if @history.length > @HISTORY_SIZE
		fs.write @history_fd, @_code+"\r\n"
		
		code = Recode @_code
		@_code = ''
		echo "Recoded: #{code}"
		try
			Fiber(=>
				_ = global._
				returnValue = coffee.eval "_=(#{code}\n)"
				if returnValue is undefined
					global._ = _
				else
					echo returnValue
			).run()
		catch err
			@error err

		@setPrompt()
		@prompt()
	
	execute: (cmd) ->
		fiber = Fiber.current
		@pause()
		cmdargs = ["-ic", "#{cmd}"]
		proc = spawn '/bin/sh', cmdargs, {cwd: process.cwd(), env: process.env, customFds: [0,1,2]}
		proc.on 'exit', (exitcode, signal) =>
			@input.removeAllListeners 'keypress'
			@input.removeListener 'data', @_data_listener
			fiber.run()
			@resume()
		yield()
		return


extend((root.shl = new Shell()), require("./coffeeshrc"))
extend(root.shl.ALIASES, require('./coffeesh_aliases'))
root.shl.init()