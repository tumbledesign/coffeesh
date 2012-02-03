#!/usr/bin/env coffee
# Coffeescript Shell
{helpers:{starts,ends,compact,count,merge,extend,flatten,del,last}} = coffee = require 'coffee-script'
{inspect,print,format,puts,debug,log,isArray,isRegExp,isDate,isError} = util = require 'util'
{EventEmitter} = require('events')
{dirname,basename,extname,exists,existsSync} = path = require('path')
{spawn,fork,exec,execFile} = require('child_process')
{Lexer} = require './lexer'
[tty,vm,fs,colors] = [require('tty'), require('vm'), require('fs'), require('colors')]

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
	
		## Config
		# STDIO
		@input = process.stdin
		@output = process.stdout
		@stderr = process.stderr
		process.on 'uncaughtException', -> @error
		
		# load history
		@SHELL_HISTORY_FILE = process.env.HOME + '/.coffee_history'
		@kHistorySize = 30
		@kBufSize = 10 * 1024
		@history_fd = fs.openSync @SHELL_HISTORY_FILE, 'a+', '644'
		@history = fs.readFileSync(@SHELL_HISTORY_FILE, 'utf-8').split('\n').reverse()
		@history.shift()
		@historyIndex = -1
		
		# Shell Prompt		
		@SHELL_PROMPT_CONTINUATION = '......> '.green
		
		
		# Autocomplete
		# Regexes to match complete-able bits of text.
		@ACCESSOR  = /([\w\.]+)(?:\.(\w*))$/
		@SIMPLEVAR = /^(?![\/\.])(\w+)$/i
		@completer = (v, callback) ->
			callback null, @autocomplete(v)
		
		@winSize = @output.getWindowSize()
		@columns = @winSize[0]
		if process.listeners("SIGWINCH").length is 0
			process.on "SIGWINCH", =>
				@winSize = @output.getWindowSize()
				@columns = @winSize[0]

		@resume()

	setPrompt: (prompt) ->
		prompt ?= "#{process.env.USER}:#{process.cwd()}$ "
		@_prompt = prompt.blue
		@_promptLength = prompt.length
		
	error: (err) -> 
		process.stdout.write (err.stack or err.toString()) + '\n'

	commonPrefix: (strings) ->
		return ""  if not strings or strings.length is 0
		sorted = strings.slice().sort()
		min = sorted[0]
		max = sorted[sorted.length - 1]
		return min.slice(0, i) for i in [0...min.length] when min[i] isnt max[i]
		min

	pause: ->
		@cursor = 0
		@line = ''
		@setPrompt ''
		@prompt()
		
		
		@input.removeAllListeners 'keypress'
		@input.pause()
		tty.setRawMode false
		return 
	
	resume: ->
		@input.setEncoding('utf8')
		@input.on("keypress", (s, key) =>
			@_ttyWrite(s, key)
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

	prompt: (preserveCursor) ->
		@cursor = 0  unless preserveCursor
		@_refreshLine()

	question: (query, cb) ->
		if cb
			#@resume()
			if @_questionCallback
				@output.write "\n"
				@prompt()
			else
				@_oldPrompt = @_prompt
				@setPrompt query
				@_questionCallback = cb
				@output.write "\n"
				@prompt()

	_onLine: (line) ->
		if @_questionCallback
			cb = @_questionCallback
			@_questionCallback = null
			@setPrompt @_oldPrompt
			cb line
		else
			@runline line

	_addHistory: ->
		return ""  if @line.length is 0
		@history.unshift @line
		@line = ""
		@historyIndex = -1
		@cursor = 0
		@history.pop()  if @history.length > @kHistorySize
		@history[0]

	_refreshLine: ->
		@output.cursorTo 0
		@output.write @_prompt
		@output.write @line
		@output.clearLine 1
		@output.cursorTo @_promptLength + @cursor


	write: (d, key) ->
		@_ttyWrite(d, key)

	_insertString: (c) ->
		#console.log c
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
		self = this
		#tty.setRawMode false
		self.completer self.line.slice(0, self.cursor), (err, rv) ->
			#tty.setRawMode true
			return  if err

			completions = rv[0]
			completeOn = rv[1]
			if completions and completions.length

				if completions.length is 1
					self._insertString completions[0].slice(completeOn.length)
				else
					handleGroup = (group) ->
						return  if group.length is 0

						minRows = Math.ceil(group.length / maxColumns)
												
						for row in [0...minRows]
							for col in [0...maxColumns]
								idx = row * maxColumns + col
								break  if idx >= group.length

								self.output.write group[idx]
								
								self.output.write " " for s in [0...(width-group[idx].length)] when (col < maxColumns - 1)

							self.output.write "\r\n"

						self.output.write "\r\n"
					
					self.output.write "\r\n"
					
					width = completions.reduce((a, b) ->
						(if a.length > b.length then a else b)
					).length + 2
					
					maxColumns = Math.floor(self.columns / width) or 1
					group = []
					c = undefined
					i = 0
					compLen = completions.length

					while i < compLen
						c = completions[i]
						if c is ""
							handleGroup group
							group = []
						else
							group.push c
						i++
					handleGroup group
					f = completions.filter (e) ->
						e if e
					
					prefix = self.commonPrefix(f)

					self._insertString prefix.slice(completeOn.length)  if prefix.length > completeOn.length
				
				self._refreshLine()

	_wordLeft: ->
		if @cursor > 0
			leading = @line.slice(0, @cursor)
			match = leading.match(/([^\w\s]+|\w+|)\s*$/)
			@cursor -= match[0].length
			@_refreshLine()

	_wordRight: ->
		if @cursor < @line.length
			trailing = @line.slice(@cursor)
			match = trailing.match(/^(\s+|\W+|\w+)\s*/)
			@cursor += match[0].length
			@_refreshLine()

	_deleteLeft: ->
		if @cursor > 0 and @line.length > 0
			@line = @line.slice(0, @cursor - 1) + @line.slice(@cursor, @line.length)
			@cursor--
			@_refreshLine()

	_deleteRight: ->
		@line = @line.slice(0, @cursor) + @line.slice(@cursor + 1, @line.length)
		@_refreshLine()

	_deleteWordLeft: ->
		if @cursor > 0
			leading = @line.slice(0, @cursor)
			match = leading.match(/([^\w\s]+|\w+|)\s*$/)
			leading = leading.slice(0, leading.length - match[0].length)
			@line = leading + @line.slice(@cursor, @line.length)
			@cursor = leading.length
			@_refreshLine()

	_deleteWordRight: ->
		if @cursor < @line.length
			trailing = @line.slice(@cursor)
			match = trailing.match(/^(\s+|\W+|\w+)\s*/)
			@line = @line.slice(0, @cursor) + trailing.slice(match[0].length)
			@_refreshLine()

	_deleteLineLeft: ->
		@line = @line.slice(@cursor)
		@cursor = 0
		@_refreshLine()

	_deleteLineRight: ->
		@line = @line.slice(0, @cursor)
		@_refreshLine()

	_line: ->
		line = @_addHistory()
		@output.write "\r\n"
		@_onLine line

	_historyNext: ->
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

	_historyPrev: ->
		if @historyIndex + 1 < @history.length
			@historyIndex++
			@line = @history[@historyIndex]
			@cursor = @line.length
			@_refreshLine()




	_ttyWrite: (s, key) ->
		key ?= {}
		
		# 	if s is '\r'
		# 		console.log()
		# 		stdout.write SHELL_PROMPT_CONTINUATION
		# 		return

		# 	else if s is '\n'
		# 		#console.log([buf])
				
		# 		#writeline()
		# 		console.log()
		# 		stdin.removeAllListeners 'keypress'
		# 		tty.setRawMode false
		# 		runline(buf)
		# 		buf = ''
		# 		return


		if key.ctrl and key.shift
			switch key.name
				when "backspace"
					@_deleteLineLeft()
				when "delete"
					@_deleteLineRight()
		else if key.ctrl
			switch key.name
				when "c"
					console.log()
					#proc = spawn './bin/coffee-shell', '',
					#	cwd: process.cwd()
					#	env: process.env
					#	setsid: false
					#	customFds:[0,1,2]
					#process.stdin.pause()
					#proc.stdin.resume()
					@pause()
					@resume()
				when "h"
					@_deleteLeft()
				when "d"
					@close()
					#if @cursor is 0 and @line.length is 0
					#	@_attemptClose()
					#else @_deleteRight()  if @cursor < @line.length
				when "u"
					@cursor = 0
					@line = ""
					@_refreshLine()
				when "k"
					@_deleteLineRight()
				when "a"
					@cursor = 0
					@_refreshLine()
				when "e"
					@cursor = @line.length
					@_refreshLine()
				when "b"
					if @cursor > 0
						@cursor--
						@_refreshLine()
				when "f"
					unless @cursor is @line.length
						@cursor++
						@_refreshLine()
				when "n"
					@_historyNext()
				when "p"
					@_historyPrev()
				when "z"
					return process.kill process.pid, "SIGTSTP"
				when "w", "backspace"
					@_deleteWordLeft()
				when "delete"
					@_deleteWordRight()
				when "backspace"
					@_deleteWordLeft()
				when "left"
					@_wordLeft()
				when "right"
					@_wordRight()
		else if key.meta
			switch key.name
				when "b"
					@_wordLeft()
				when "f"
					@_wordRight()
				when "d", "delete"
					@_deleteWordRight()
				when "backspace"
					@_deleteWordLeft()
# 			when "n"
# 				nanoprompt()
		else
			switch key.name
				when "enter"
					@_line()
					#@prompt()

				when "backspace"
					@_deleteLeft()
				when "delete"
					@_deleteRight()
				when "tab"
					@_tabComplete()
				when "left"
					if @cursor > 0
						@cursor--
						@output.moveCursor -1, 0
				when "right"
					unless @cursor is @line.length
						@cursor++
						@output.moveCursor 1, 0
				when "home"
					@cursor = 0
					@_refreshLine()
				when "end"
					@cursor = @line.length
					@_refreshLine()
				when "up"
					@_historyPrev()
				when "down"
					@_historyNext()
				else
					s = s.toString("utf-8")  if Buffer.isBuffer(s)
					if s
						lines = s.split(/\r\n|\n|\r/)
						i = 0
						len = lines.length

						while i < len
							@_line()  if i > 0
							@_insertString lines[i]
							i++
							
	runline: (buffer) ->
		#return @prompt()
		if !buffer.toString().trim() 
			return @prompt()
			
		code = buffer
		recode = @tokenparse code
		echo "Recoded: #{recode}"
		try
			_ = global._
			returnValue = coffee.eval "_=(#{recode}\n)"
			if returnValue is undefined
				global._ = _
			else
				print inspect(returnValue, no, 2, true) + '\n'
			fs.write @history_fd, code + '\n'
		catch err
			@error err
		@prompt()

	tokenparse: (code) ->

		tokens = (new Lexer).tokenize code
		output = []
		
		for i in [0...tokens.length]
			[lex,val] = tokens[i]
			echo tokens[i]
			switch lex
				when 'IDENTIFIER'
					if builtin.hasOwnProperty val
						output.push "builtin.#{val}"
					else if binaries.hasOwnProperty val
						cmd = Lexer.prototype.makeString "#{binaries[val]}/#{val}", '"', yes
						output.push "shl.execute.bind(shl,#{cmd})"
						if tokens[i+1]?[0] is 'TERMINATOR'
							output.push '()'
					else
						output.push val
				when 'STRING'
					output.push val
				when '=', '(', ')', '{', '}', '[', ']', ':', '.', '->', ',', '...'
					output.push lex
				when 'INDEX_START', 'INDEX_END', 'CALL_START', 'CALL_END', 'FOR', 'FORIN', 'FOROF', 'PARAM_START', 'PARAM_END', 'IF', 'POST_IF'
					output.push val
					output.push ' ' if tokens[i].spaced?
				when 'TERMINATOR'
					output.push "\n"
				when 'FILEPATH'
					if tokens[i+1]?[0] in ['CALL_START', '(']
						output.push "shl.execute.bind(shl,#{val})"
					else if tokens[i+1]?[0] is 'TERMINATOR'
						output.push "shl.execute(#{val})"
					else
						output.push val
				when 'BOOL', 'NUMBER', '1', '2', '3', '4', '5', '6', '7', '8', '9', '0'
					output.push val
				when 'MATH'
					output.push val
				when 'INDENT'
					output.push " then " if tokens[i].fromThen
			
			
		(output.join(''))
	
	
	execute: (cmd, args...) ->
		@pause()
		proc = spawn cmd, args,
			cwd: process.cwd()
			env: process.env
			setsid: false
			customFds:[0,1,2]
		proc.on 'exit', =>
			@resume()
		return
			
		

	## Autocompletion

	# Returns a list of completions, and the completed text.
	autocomplete: (text) ->
		prefix = filePrefix = builtinPrefix = binaryPrefix = accessorPrefix = varPrefix = null
		completions = fileCompletions = builtinCompletions = binaryCompletions = accessorCompletions = varCompletions = []
		
		text = text.substr 0, @cursor
		text = text.split(' ').pop()

		# Attempt to autocomplete a valid file or directory
		isdir = (text is "" or text[text.length-1] is '/')
		dir = path.resolve text, (if isdir then '.' else '..')
		filePrefix = (if isdir then	'' else path.basename text)
		if path.existsSync dir then listing = fs.readdirSync dir
		else listing = fs.readdirSync '.'
		fileCompletions = (el for el in listing when el.indexOf(filePrefix) is 0)
		
		# Attempt to autocomplete a builtin cmd
		builtinPrefix = text
		builtinCompletions = (cmd for cmd in Object.getOwnPropertyNames(builtin) when cmd.indexOf(builtinPrefix) is 0)
		
		# Attempt to autocomplete a valid executable
		binaryPrefix = text
		binaryCompletions = (cmd for cmd in Object.getOwnPropertyNames(binaries) when cmd.indexOf(binaryPrefix) is 0)
		
		# Attempt to autocomplete a chained dotted attribute: `one.two.three`.
		if match = text.match @ACCESSOR
		#console.log match
		#if match?
			[all, obj, accessorPrefix] = match
			try
				val = vm.runInThisContext obj
				accessorCompletions = (el for el in Object.getOwnPropertyNames(Object(val)) when el.indexOf(accessorPrefix) is 0)
			catch error
				accessorCompletions = []
				accessorPrefix = null
			
		# Attempt to autocomplete an in-scope free variable: `one`.
		varPrefix = text.match(@SIMPLEVAR)?[1]
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
		([completions, prefix])
		
exports.Shell = Shell
root.shl = new Shell()