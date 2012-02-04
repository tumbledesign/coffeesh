# Coffeescript Shell
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
for pathname in (process.env.PATH.split ':')
	if path.existsSync(pathname) 
		binaries[file] = pathname for file in fs.readdirSync(pathname)

builtin = 
	cd: (to) -> 
		if to.indexOf('~') is 0
			to = shl.home + to.substr(1)
		newcwd = shl.cwd
		if newcwd.indexOf('~') is 0
			newcwd = shl.home + newcwd.substr(1)
			
		newcwd = path.resolve newcwd, to
		return if not path.existsSync(newcwd)?
		process.chdir newcwd
		process.env.PWD = newcwd
		if newcwd.indexOf(shl.home) is 0
			shl.cwd =	'~'+newcwd.substr(shl.home.length)
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
		@MOUSETRACK = "\x1b[?1003h\x1b[?1005h"
		@MOUSEUNTRACK = "\x1b[?1003l\x1b[?1005l"
		@HOSTNAME = os.hostname()
		@HISTORY_FILE = process.env.HOME + '/.coffee_history'
		@HISTORY_FILE_SIZE = 1000 # TODO: implement this
		@HISTORY_SIZE = 300
		@PROMPT_CONTINUATION = => ('......> '.green)
		@PROMPT = => ("#{@HOSTNAME.white}:#{@cwd.blue.bold} #{if @user is 'root' then "➜".red else "➜".green}  ")
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
		@cwd = process.cwd()
		@user = process.env.USER
		@home = process.env.HOME
			
		process.on 'uncaughtException', -> @error
		
	init: ->
		@numlines = @atline = 0
	
		# load history
		# TODO: make loading history async so no hang on big files
		@history_fd = fs.openSync @HISTORY_FILE, 'a+', '644'
		@history = fs.readFileSync(@HISTORY_FILE, 'utf-8').split("\r\n").reverse()
		@history.shift()
		@historyIndex = -1
		
		# window size
		@winSize = @output.getWindowSize()
		@columns = @winSize[0]
		if process.listeners("SIGWINCH").length is 0
			process.on "SIGWINCH", =>
				@winSize = @output.getWindowSize()
				@columns = @winSize[0]

		@consecutive_tabs = 0

		# command aliases
		for alias,val of @ALIASES when not builtin[alias]? and binaries[val.split(' ')[0]]?
			builtin[alias] = (params...) -> 
				shl.execute binaries[val.split(' ')[0]] + '/' + val + " " + params.join(" ")

		# connect to tty
		@resume()		

	error: (err) -> 
		process.stderr.write (err.stack or err.toString()) + '\n'

	resume: ->
		@input.setEncoding('utf8')
		@mtrack = (s) =>
			return if (s.length < 5)
			modifier = s.charCodeAt(3)
			key =
				shift: !!(modifier & 4)
				meta: !!(modifier & 8)
				ctrl: !!(modifier & 16)
				button: null
				x: s.charCodeAt(4) - 33
				y: s.charCodeAt(5) - 33
			#console.log s.charCodeAt(0), s.charCodeAt(1), s.charCodeAt(2), s.charCodeAt(3), (s.charCodeAt(4) & 255), s.charCodeAt(5)
			if ((modifier & 96) is 96)
				key.name = 'scroll'
				key.button = if modifier & 1 then 'down' else 'up'
			else
				key.name = if modifier & 64 then 'move' else 'click'
				switch (modifier & 3)
					when 0 then key.button = 'left'
					when 1 then key.button = 'middle'
					when 2 then key.button = 'right'
					when 3 then key.button = 'none'
					else return
			@write('', key)
			
		@input.on('data', @mtrack)
		@input.on("keypress", (s, key) => @write(s, key)).resume()
		tty.setRawMode true
		@output.write(@MOUSETRACK)
		
		@cursor = 0
		@line = ''
		@code = ''
		@setPrompt()
		@prompt()
		return

	pause: ->
		@cursor = 0
		@line = ''
		@code = ''
		@output.clearLine 0
		@input.removeAllListeners 'keypress'
		@input.removeListener 'data', @mtrack
		console.log(@MOUSEUNTRACK)
		@input.pause()
		tty.setRawMode false
		return 

	close: ->
		@input.removeAllListeners 'keypress'
		@input.removeAllListeners 'data'
		console.log(@MOUSEUNTRACK)
		tty.setRawMode false
		@input.destroy()
		return

	setPrompt: (p) ->
		p ?= @PROMPT
		@_prompt = p()
			
	prompt: ->
		@line = ""
		@historyIndex = -1
		@cursor = 0 
		@refreshLine()

	refreshLine: ->
		@output.cursorTo 0
		@output.write @_prompt
		@output.write @line
		@output.clearLine 1
		@output.cursorTo @_prompt.stripColors.length + @cursor


	write: (s, key) ->
		key ?= {}
		
		# enter
		if s is '\r'
			@code += @line
			@numlines = @code.split('\n').length-1
			@atline = @numlines
			@runline()
			return
			
		# ctrl enter
		else if s is '\n'
			@insertString '\n'
			@code += @line
			@numlines = @code.split('\n').length-1
			@atline = @numlines
			@setPrompt @PROMPT_CONTINUATION
			@prompt()
			return
			
		keytoken = (if key.ctrl then "C^" else "") + (if key.meta then "M^" else "") + (if key.shift then "S^" else "") + key.name
		if keytoken is "tab" then @consecutive_tabs++ else @consecutive_tabs = 0
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
				@close() if @cursor is 0 and @line.length is 0

			when "tab" then @tabComplete()
			#when "enter" then @runline()

			# Clear line
			when "C^u"
				@cursor = 0
				@line = ""
				@refreshLine()

		## Deletions

			when "backspace", "C^h"
				if @cursor > 0 and @line.length > 0
					@line = @line.slice(0, @cursor - 1) + @line.slice(@cursor, @line.length)
					@cursor--
					@refreshLine()
				else
					if @code.length > 0
						code = @code.split('\n')
						code.pop()
						code.unshift()
						#@code = code.join('\n')
						@code = @line = ''
						for i in [0...code.length]
							@output.clearLine 0
							@output.cursorTo 0
							@output.moveCursor 0,-1
							@output.clearLine 0
							@output.cursorTo 0
							@cursor = code[i].length
							if i is 0
								@setPrompt()
								@line = code[i] + (if i < code.length-1 then '\n' else '')
								@refreshLine()
							else
								@setPrompt @PROMPT_CONTINUATION
								@line = code[i] + (if i < code.length-1 then '\n' else '')
								@refreshLine()
							if i < code.length - 1
								@code += @line
								@numlines = @code.split('\n').length-1
								@atline = @numlines
			when "delete", "C^d"
				if @cursor < @line.length
					@line = @line.slice(0, @cursor) + @line.slice(@cursor + 1, @line.length)
					@refreshLine()
			# Word left
			when "C^w", "C^backspace", "M^backspace"
				if @cursor > 0
					leading = @line.slice(0, @cursor)
					match = leading.match(/([^\w\s]+|\w+|)\s*$/)
					leading = leading.slice(0, leading.length - match[0].length)
					@line = leading + @line.slice(@cursor, @line.length)
					@cursor = leading.length
					@refreshLine()
			# Word right
			when "C^delete", "M^d", "M^delete"
				if @cursor < @line.length
					trailing = @line.slice(@cursor)
					match = trailing.match(/^(\s+|\W+|\w+)\s*/)
					@line = @line.slice(0, @cursor) + trailing.slice(match[0].length)
					@refreshLine()
			# Line right
			when "C^k", "C^S^delete"
				@line = @line.slice(0, @cursor)
				@refreshLine()
			# Line left
			when "C^S^backspace"
				@line = @line.slice(@cursor)
				@cursor = 0
				@refreshLine()

		## Cursor Movements

			when "home", "C^a"
				@cursor = 0
				@refreshLine()
			when "end", "C^e"
				@cursor = @line.length
				@refreshLine()
			when "left", "C^b"
				if @cursor > 0
					@cursor--
					@output.moveCursor -1, 0
			when "right", "C^f"
				unless @cursor is @line.length
					@cursor++
					@output.moveCursor 1, 0
			# Word left
			when "C^left", "M^b"
				if @cursor > 0
					leading = @line.slice(0, @cursor)
					match = leading.match(/([^\w\s]+|\w+|)\s*$/)
					@cursor -= match[0].length
					@refreshLine()
			# Word right
			when "C^right", "M^f"
				if @cursor < @line.length
					trailing = @line.slice(@cursor)
					match = trailing.match(/^(\s+|\W+|\w+)\s*/)
					@cursor += match[0].length
					@refreshLine()


		## History
			when "up", "C^p", "down", "C^n"
				if keytoken in ['up', 'C^p'] and @atline > 0 and @atline <= @numlines and @numlines > 0
					@atline--
					@output.moveCursor 0, -1
					return
				else if keytoken in ['down', 'C^n'] and @atline < @numlines and @atline >= 0 and @numlines > 0
					@atline++
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
					@cursor = 0
					@line = ""
					@code = ""
					@setPrompt()
					@refreshLine()
					return
				else return

				@line = @code = ''
				code = @history[@historyIndex]
				lns = code.split('\n')
				@numlines = lns.length-1
				@atline = @numlines
				
				for i in [0...lns.length]
					@output.clearLine 0
					@output.cursorTo 0
					@cursor = lns[i].length
					if i is 0
						@setPrompt()
						@line = lns[i] + (if i < lns.length-1 then '\n' else '')
						@refreshLine()
					else
						@setPrompt @PROMPT_CONTINUATION
						@line = lns[i] + (if i < lns.length-1 then '\n' else '')
						@refreshLine()
					if i < lns.length - 1
						@code += @line
						#@numlines = @code.split('\n').length-1
						#@atline = @numlines
					#@line = ''
		## Directly output char to terminal
			else
				s = s.toString("utf-8") if Buffer.isBuffer(s)
				if s
					lines = s.split /\r\n|\n|\r/
					for i,line of lines
						@runline() if i > 0
						@insertString lines[i]

	insertString: (c) ->
		if @cursor < @line.length
			beg = @line.slice(0, @cursor)
			end = @line.slice(@cursor, @line.length)
			@line = beg + c + end
			@cursor += c.length
			@refreshLine()
		else
			@line += c
			@cursor += c.length
			@output.write c

	tabComplete: ->
		@autocomplete( @line.slice(0, @cursor).split(' ').pop(), ( (completions, completeOn) =>
			if completions and completions.length
				if completions.length is 1
					@insertString completions[0].slice(completeOn.length)
				else
					@output.write "\r\n"
					
					width = completions.reduce((a, b) ->
						(if a.length > b.length then a else b)
					).length + 2
					
					maxColumns = Math.floor(@columns / width) or 1
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
		if !@code.toString().trim()
			@setPrompt()
			@prompt()
			return

		@history.unshift @code
		@history.pop() if @history.length > @HISTORY_SIZE
		fs.write @history_fd, @code+"\r\n"
		
		code = Recode @code
		@code = ''
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
		#@pause()
		lastcmd = ''
		proc = spawn '/bin/sh', ["-c", "#{cmd}"]
		proc.stdout.on 'data', (data) =>
			#console.log data.toString()
			lastcmd = data.toString().trim()
		proc.stderr.on 'data', (data) =>
			console.log data.toString()		
		proc.on 'exit', (exitcode, signal) =>
			#@input.removeAllListeners 'keypress'
			#@input.removeListener 'data', @mtrack
			#@output.write(@MOUSEUNTRACK)
			fiber.run()
			#@resume()
		yield()
		return lastcmd
		
	interactive: (cmd) ->
		fiber = Fiber.current
		@pause()
		cmdargs = ["-ic", "#{cmd}"]
		proc = spawn '/bin/sh', cmdargs, {cwd: process.cwd(), env: process.env, customFds: [0,1,2]}
		proc.on 'exit', (exitcode, signal) =>
			@input.removeAllListeners 'keypress'
			@input.removeListener 'data', @mtrack
			@output.write(@MOUSEUNTRACK)
			fiber.run()
			@resume()
		yield()
		return



extend((root.shl = new Shell()), require("./coffeeshrc"))
extend(root.shl.ALIASES, require('./coffeesh_aliases'))
root.shl.init()
#root.shl.cwd = shl.execute("/bin/pwd -L")
#if root.shl.cwd.indexOf(root.shl.home) is 0
#	root.shl.cwd =	'~'+root.shl.cwd.substr(root.shl.home.length)