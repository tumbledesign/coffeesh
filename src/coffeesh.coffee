#!/usr/bin/env coffee
# Coffeescript Shell
{helpers:{starts,ends,compact,count,merge,extend,flatten,del,last}} = coffee = require 'coffee-script'
{inspect,print,format,puts,debug,log,isArray,isRegExp,isDate,isError} = util = require 'util'
{EventEmitter} = require('events')
{dirname,basename,extname,exists,existsSync} = path = require('path')
{spawn,fork,exec,execFile} = require('child_process')
{Recode} = require './recode'
[tty,vm,fs,colors] = [require('tty'), require('vm'), require('fs'), require('colors')]
os = require 'os'
require 'fibers'

#Load binaries and built-in shell commands
binaries = {}
for pathname in (process.env.PATH.split ':')
	if path.existsSync(pathname) 
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
		@SHELL_PROMPT_CONTINUATION = '......> '.green
		@_ALIASES = 
			ls: 'ls --color=auto'
			l: 'ls -latr --color=auto'
			grep: 'grep --color=auto'
			egrep: 'egrep --color=auto'
			fgrep: 'fgrep --color=auto'
		
	init: ->
		# STDIO
		@input = process.stdin
		@output = process.stdout
		@stderr = process.stderr
		process.on 'uncaughtException', -> @error
		
		# load history
		@history_fd = fs.openSync @HISTORY_FILE, 'a+', '644'
		# TODO: make loading history async so no hang on big files
		@history = fs.readFileSync(@HISTORY_FILE, 'utf-8').split('\n').reverse()
		@history.shift()
		@historyIndex = -1
			
		@winSize = @output.getWindowSize()
		@columns = @winSize[0]
		if process.listeners("SIGWINCH").length is 0
			process.on "SIGWINCH", =>
				@winSize = @output.getWindowSize()
				@columns = @winSize[0]

		@consecutive_tabs = 0

		extend @_ALIASES, @ALIASES
		for alias,val of @_ALIASES
			do (alias, val) ->
				cmd = val.split(" ").shift()
				if not builtin[alias]? and binaries[cmd]?
					builtin[alias] = (params...) ->
						shl.execute binaries[cmd] + '/' + val + " " + params.join(" ")

		@resume()

	setPrompt: (prompt, length) ->
		if prompt?
			@_prompt = prompt
			@_promptLength = length
		else
			usr = "#{process.env.USER}@#{@hostname}"
			cwd = "#{process.cwd()}"
			@_prompt = "#{usr.blue.bold}:#{cwd.green.bold}$ "
			@_promptLength = usr.length + cwd.length + 3
		
	error: (err) -> 
		process.stderr.write (err.stack or err.toString()) + '\n'


	pause: ->
		@cursor = 0
		@line = ''
		@setPrompt '', 0
		@prompt()
		@input.removeAllListeners 'keypress'
		@input.pause()
		tty.setRawMode false
		return 
	
	resume: ->
		@input.setEncoding('utf8')
		@input.on("keypress", (s, key) =>
			@write(s, key)
		).resume()
		tty.setRawMode true
		
		@cursor = 0
		@line = ''
		@setPrompt()
		@prompt()
		return

	close: ->
		@input.removeAllListeners 'keypress'
		tty.setRawMode false
		@input.destroy()
		return

	prompt: ->
		@line = ""
		@historyIndex = -1
		@cursor = 0 
		@_refreshLine()

	_refreshLine: ->
		@output.cursorTo 0
		@output.write @_prompt
		@output.write @line
		@output.clearLine 1
		@output.cursorTo @_promptLength + @cursor


	write: (s, key) ->
		key ?= {}
		
		# 	if s is '\r'
		# 		console.log()
		# 		stdout.write SHELL_PROMPT_CONTINUATION
		# 		return

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

			when "tab" then @_tabComplete()
			when "enter" then @runline()

			# Clear line
			when "C^u"
				@cursor = 0
				@line = ""
				@_refreshLine()

		## Deletions

			when "backspace", "C^h"
				if @cursor > 0 and @line.length > 0
					@line = @line.slice(0, @cursor - 1) + @line.slice(@cursor, @line.length)
					@cursor--
					@_refreshLine()
			when "delete", "C^d"
				if @cursor < @line.length
					@line = @line.slice(0, @cursor) + @line.slice(@cursor + 1, @line.length)
					@_refreshLine()
			# Word left
			when "C^w", "C^backspace", "M^backspace"
				if @cursor > 0
					leading = @line.slice(0, @cursor)
					match = leading.match(/([^\w\s]+|\w+|)\s*$/)
					leading = leading.slice(0, leading.length - match[0].length)
					@line = leading + @line.slice(@cursor, @line.length)
					@cursor = leading.length
					@_refreshLine()
			# Word right
			when "C^delete", "M^d", "M^delete"
				if @cursor < @line.length
					trailing = @line.slice(@cursor)
					match = trailing.match(/^(\s+|\W+|\w+)\s*/)
					@line = @line.slice(0, @cursor) + trailing.slice(match[0].length)
					@_refreshLine()
			# Line right
			when "C^k", "C^S^delete"
				@line = @line.slice(0, @cursor)
				@_refreshLine()
			# Line left
			when "C^S^backspace"
				@line = @line.slice(@cursor)
				@cursor = 0
				@_refreshLine()

		## Cursor Movements

			when "home", "C^a"
				@cursor = 0
				@_refreshLine()
			when "end", "C^e"
				@cursor = @line.length
				@_refreshLine()
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
					@_refreshLine()
			# Word right
			when "C^right", "M^f"
				if @cursor < @line.length
					trailing = @line.slice(@cursor)
					match = trailing.match(/^(\s+|\W+|\w+)\s*/)
					@cursor += match[0].length
					@_refreshLine()

		## History

			when "down", "C^n"
				if @historyIndex > 0
					@historyIndex--
					@line = @history[@historyIndex]
					@cursor = @line.length
					@_refreshLine()
				else if @historyIndex is 0
					@historyIndex = -1
					@cursor = 0
					@line = ""
					@_refreshLine()
			when "up", "C^p"
				if @historyIndex + 1 < @history.length
					@historyIndex++
					@line = @history[@historyIndex]
					@cursor = @line.length
					@_refreshLine()
			
		## Directly output char to terminal
			else
				s = s.toString("utf-8") if Buffer.isBuffer(s)
				if s
					lines = s.split /\r\n|\n|\r/
					for i,line of lines
						@runline() if i > 0
						@_insertString lines[i]

	_insertString: (c) ->
		if @cursor < @line.length
			beg = @line.slice(0, @cursor)
			end = @line.slice(@cursor, @line.length)
			@line = beg + c + end
			@cursor += c.length
			@_refreshLine()
		else
			@line += c
			@cursor += c.length
			@output.write c

	_tabComplete: ->
		@autocomplete( @line.slice(0, @cursor).split(' ').pop(), ( (completions, completeOn) =>
			if completions and completions.length
				if completions.length is 1
					@_insertString completions[0].slice(completeOn.length)
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

					@_insertString prefix.slice(completeOn.length) if prefix.length > completeOn.length
				
				@_refreshLine()
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
		if !@line.toString().trim() 
			return @prompt()

		@history.unshift @line
		@history.pop() if @history.length > @HISTORY_SIZE
		fs.write @history_fd, @line + '\n'
		code = Recode @line
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
		@prompt()
	
	execute: (cmd) ->
		fiber = Fiber.current
		@pause()
		cmdargs = ["-ic", "#{cmd}"]
		proc = spawn '/bin/sh', cmdargs, {cwd: process.cwd(), env: process.env, customFds: [0,1,2]}
		proc.on 'exit', (exitcode, signal) =>
			@input.removeAllListeners 'keypress'
			fiber.run()
			@resume()
		yield()
		return

root.shl = new Shell()
extend(root.shl, require("./coffeeshrc"))
root.shl.init()