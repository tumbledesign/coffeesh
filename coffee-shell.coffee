
#!/usr/bin/env coffee
# Coffeescript Shell
{@run,@eval,helpers:{starts,ends,compact,count,merge,extend,flatten,del,last}} = coffee = require 'coffee-script'
{inspect,print,format,puts,debug,log,isArray,isRegExp,isDate,isError} = util = require 'util'
{EventEmitter} = require('events')
{dirname,basename,extname,exists,existsSync} = path = require('path')
{spawn,fork,exec,execFile} = require('child_process')
{Lexer} = require './lexer'
[tty,vm,fs,colors] = [require('tty'), require('vm'), require('fs'), require('colors')]

sandbox = root.sandbox = null
shell = root.shell = null

keymode = off

stdin = process.stdin
stdout = process.stdout
stderr = process.stderr
output = process.stdout
input = process.stdin
line = ""
cursor = 0
history = []
historyIndex = -1
kHistorySize = 30
kBufSize = 10 * 1024
buf = ''

# Config
#shelllength = 2
SHELL_PROMPT = -> 
	u = process.env.USER
	d = process.cwd() #.replace('/home/'+u,'~')
	#shelllength = "#{u}:#{d}$ ".length
	("#{u}:#{d}$ ".green)

SHELL_PROMPT_CONTINUATION = '......> '.green

SHELL_HISTORY_FILE = process.env.HOME + '/.coffee_history'
enableColours = yes

# Log an error.
error = (err) -> process.stdout.write (err.stack or err.toString()) + '\n'
process.on 'uncaughtException', -> error


# load history
history = fs.readFileSync(SHELL_HISTORY_FILE, 'utf-8').split('\n').reverse()
history.shift()
historyIndex = -1
history_fd = fs.openSync SHELL_HISTORY_FILE, 'a+', '644'


exports.run = ->
	prompt()

prompt = ->
	buf = ''
	tty.setRawMode true
	input.setEncoding('utf8')
	
	setPrompt SHELL_PROMPT()
	output.write SHELL_PROMPT()

	input.on("keypress", (s, key) ->
		
		write s, key
		line = ""
		cursor = 0
		history = []
		historyIndex = -1

	).resume()

# 	buf = ''
# 	tty.setRawMode true
# 	stdin.setEncoding('utf8')
# 	stdout.write SHELL_PROMPT()

# 	stdin.on('keypress', (c,key) ->
# 		buf += c

# 		if not key?
# 				stdout.write c

# 		else if c is '\r'
# 			console.log()
# 			stdout.write SHELL_PROMPT_CONTINUATION

# 		else if c is '\n'
# 			#console.log([buf])
# 			console.log()
# 			stdin.removeAllListeners 'keypress'
# 			tty.setRawMode false
# 			runline(buf)
# 			buf = ''
# 			return

# 		else if key?.ctrl and key.name is 'n'
# 			buf = ''
# 			stdin.removeAllListeners 'keypress'
# 			tty.setRawMode false
# 			nanoprompt()
# 			return

# 		else if key?.ctrl and key.name is 'c'
# 			buf = ''
# 			stdin.removeAllListeners 'keypress'
# 			tty.setRawMode false
# 			console.log()
# 			prompt()
# 			return

# 		else if key?.ctrl and key.name is 'd'
# 			stdin.removeAllListeners 'keypress'
# 			tty.setRawMode false
# 			stdin.destroy()
# 			return
		
# 		else if key?.meta and key.name is 'k'
# 			keymode = not keymode


# 		else if key?.name is 'backspace'
# 			stdout.moveCursor(0)
# 			stdout.clearLine(1)

# 		else
# 			if keymode
# 				console.log key
# 			else
# 				stdout.write c

# 	).resume()





#util = require("util")
#inherits = require("util").inherits
#EventEmitter = require("events").EventEmitter
#tty = require("tty")




# otherjunk = ->
# 	#EventEmitter.call this
# 	completer = completer or -> 
# 		[]

# 	#throw new TypeError("Argument 'completer' must be a function")  if typeof completer isnt "function"

	

# 	@completer = (if completer.length is 2 then completer else (v, callback) ->
# 		callback null, completer(v)
# 	)



# 	winSize = output.getWindowSize()
# 	exports.columns = winSize[0]
# 	if process.listeners("SIGWINCH").length is 0
# 		process.on "SIGWINCH", ->
# 			winSize = output.getWindowSize()
# 			exports.columns = winSize[0]



write = (s, key) ->
	
	#return  if closed
	buf += s
	key ?= {}

	#console.log d, key

	if s is '\r'
		console.log()
		stdout.write SHELL_PROMPT_CONTINUATION

	else if s is '\n'
		#console.log([buf])
		console.log()
		stdin.removeAllListeners 'keypress'
		tty.setRawMode false
		runline(buf)
		buf = ''
		return


	else if key.ctrl and key.shift
		switch key.name
			when "backspace"
				deleteLineLeft()
			when "delete"
				deleteLineRight()

	else if key.ctrl
		switch key.name
			when "c"
				detach()
				console.log()
				prompt()
				#f listeners("SIGINT").length
				#emit "SIGINT"
				#lse
				#close()
			when "h"
				deleteLeft()
			when "d"
				if cursor is 0 and line.length is 0
					close()
				else deleteRight()  if cursor < line.length
			when "u"
				cursor = 0
				line = ""
				refreshLine()
			when "k"
				deleteLineRight()
			when "a"
				cursor = 0
				refreshLine()
			when "e"
				cursor = line.length
				refreshLine()
			when "b"
				if cursor > 0
					cursor--
					refreshLine()
			when "f"
				unless cursor is line.length
					cursor++
					refreshLine()
			when "n"
				historyNext()
			when "p"
				historyPrev()
			when "z"
				process.kill process.pid, "SIGTSTP"
				return
			when "w", "backspace"
				deleteWordLeft()
			when "delete"
				deleteWordRight()
			when "backspace"
				deleteWordLeft()
			when "left"
				wordLeft()
			when "right"
				wordRight()

	else if key.meta
		switch key.name
			when "b"
				wordLeft()
			when "f"
				wordRight()
			when "d", "delete"
				deleteWordRight()
			when "backspace"
				deleteWordLeft()

	else
		switch key.name
			#when "enter"
			#	writeline()
			when "backspace"
				deleteLeft()
			when "delete"
				deleteRight()
			when "tab"
				tabComplete()
			when "left"
				if cursor > 0
					cursor--
					output.moveCursor -1, 0
			when "right"
				unless cursor is line.length
					cursor++
					output.moveCursor 1, 0
			when "home"
				cursor = 0
				refreshLine()
			when "end"
				cursor = line.length
				refreshLine()
			when "up"
				historyPrev()
			when "down"
				historyNext()
			else
				#output.write s

				s = s.toString("utf-8")  if Buffer.isBuffer(s)
				if s
					lines = s.split(/\n/) # (/\r\n|\n|\r/)
					i = 0
					len = lines.length

					while i < len
						writeline()  if i > 0
						insertString lines[i]
						i++



detach = ->
	input.removeAllListeners 'keypress'
	tty.setRawMode false


commonPrefix = (strings) ->
	return ""  if not strings or strings.length is 0
	sorted = strings.slice().sort()
	min = sorted[0]
	max = sorted[sorted.length - 1]
	i = 0
	len = min.length

	while i < len
		return min.slice(0, i)  unless min[i] is max[i]
		i++
	min



setPrompt = (prompt, length) ->
	prompt = prompt
	if length
		promptLength = length
	else
		lines = prompt.split(/[\r\n]/)
		lastLine = lines[lines.length - 1]
		promptLength = Buffer.byteLength(lastLine)

#prompt = (preserveCursor) ->
#	if enabled
#		cursor = 0  unless preserveCursor
#		refreshLine()
#	else
#		output.write prompt

question = (query, cb) ->
	if cb
		tty.setRawMode true
		if questionCallback
			output.write "\n"
			prompt()
		else
			oldPrompt = prompt
			setPrompt query
			questionCallback = cb
			output.write "\n"
			prompt()

onLine = (line) ->
	if questionCallback
		cb = questionCallback
		questionCallback = null
		setPrompt oldPrompt
		cb line
	#else
	#	emit "line", line

addHistory = ->
	return ""  if line.length is 0
	history.unshift line
	line = ""
	historyIndex = -1
	cursor = 0
	history.pop()  if history.length > kHistorySize
	history[0]

refreshLine = ->
	return  if closed
	output.cursorTo 0
	output.write prompt
	output.write line
	output.clearLine 1
	output.cursorTo promptLength + cursor

close = (d) ->
	input.removeAllListeners 'keypress'
	tty.setRawMode false
	closed = true
	input.destroy()
	return

insertString = (c) ->
	if cursor < line.length
		beg = line.slice(0, cursor)
		end = line.slice(cursor, line.length)
		line = beg + c + end
		cursor += c.length
		refreshLine()
	else
		line += c
		cursor += c.length
		output.write c

# _tabComplete = ->
# 	tty.setRawMode false
# 	completer line.slice(0, cursor), (err, rv) ->
# 		tty.setRawMode true
# 		return  if err
# 		completions = rv[0]
# 		completeOn = rv[1]
# 		if completions and completions.length
# 			if completions.length is 1
# 				insertString completions[0].slice(completeOn.length)
# 			else
# 				handleGroup = (group) ->
# 					return  if group.length is 0
# 					minRows = Math.ceil(group.length / maxColumns)
# 					row = 0

# 					while row < minRows
# 						col = 0

# 						while col < maxColumns
# 							idx = row * maxColumns + col
# 							break  if idx >= group.length
# 							item = group[idx]
# 							output.write item
# 							if col < maxColumns - 1
# 								s = 0
# 								itemLen = item.length

# 								while s < width - itemLen
# 									output.write " "
# 									s++
# 							col++
# 						output.write "\r\n"
# 						row++
# 					output.write "\r\n"
# 				output.write "\r\n"
# 				width = completions.reduce((a, b) ->
# 					(if a.length > b.length then a else b)
# 				).length + 2
# 				maxColumns = Math.floor(columns / width) or 1
# 				group = []
# 				c = undefined
# 				i = 0
# 				compLen = completions.length

# 				while i < compLen
# 					c = completions[i]
# 					if c is ""
# 						handleGroup group
# 						group = []
# 					else
# 						group.push c
# 					i++
# 				handleGroup group
# 				f = completions.filter((e) ->
# 					e  if e
# 				)
# 				prefix = commonPrefix(f)
# 				insertString prefix.slice(completeOn.length)  if prefix.length > completeOn.length
# 			refreshLine()

wordLeft = ->
	if cursor > 0
		leading = line.slice(0, cursor)
		match = leading.match(/([^\w\s]+|\w+|)\s*$/)
		cursor -= match[0].length
		refreshLine()

wordRight = ->
	if cursor < line.length
		trailing = line.slice(cursor)
		match = trailing.match(/^(\s+|\W+|\w+)\s*/)
		cursor += match[0].length
		refreshLine()

deleteLeft = ->
	if cursor > 0 and line.length > 0
		line = line.slice(0, cursor - 1) + line.slice(cursor, line.length)
		cursor--
		refreshLine()

deleteRight = ->
	line = line.slice(0, cursor) + line.slice(cursor + 1, line.length)
	refreshLine()

deleteWordLeft = ->
	if cursor > 0
		leading = line.slice(0, cursor)
		match = leading.match(/([^\w\s]+|\w+|)\s*$/)
		leading = leading.slice(0, leading.length - match[0].length)
		line = leading + line.slice(cursor, line.length)
		cursor = leading.length
		refreshLine()

deleteWordRight = ->
	if cursor < line.length
		trailing = line.slice(cursor)
		match = trailing.match(/^(\s+|\W+|\w+)\s*/)
		line = line.slice(0, cursor) + trailing.slice(match[0].length)
		refreshLine()

deleteLineLeft = ->
	line = line.slice(cursor)
	cursor = 0
	refreshLine()

deleteLineRight = ->
	line = line.slice(0, cursor)
	refreshLine()

writeline = ->
	line = addHistory()
	output.write "\r\n"
	onLine line

historyNext = ->
	if historyIndex > 0
		historyIndex--
		line = history[historyIndex]
		cursor = line.length
		refreshLine()
	else if historyIndex is 0
		historyIndex = -1
		cursor = 0
		line = ""
		refreshLine()

historyPrev = ->
	if historyIndex + 1 < history.length
		historyIndex++
		line = history[historyIndex]
		cursor = line.length
		refreshLine()















runline = (buffer) ->
	#return if shell.blockingProc

	if !buffer.toString().trim() #and !shell.backlog
		prompt()
		return

	#code = shell.backlog += buffer
	
	#if code[code.length - 1] is '\\'
	#	shell.backlog = "#{shell.backlog[...-1]}\n"
	#	shell.setPrompt SHELL_PROMPT_CONTINUATION
	#	prompt()
	#	return
	
	#shell.backlog = ''

	code = buffer

	try
		
		#recode = tokenparse code
		#console.log code, recode

		_ = sandbox._
		
		returnValue = coffee.eval "_=(#{code}\n)",
			sandbox,
			filename: __filename
			modulename: module.id

		if returnValue is undefined
			sandbox._ = _
		else
			process.stdout.write inspect(returnValue, no, 2, enableColours) + '\n'
		
		fs.write history_fd, code + '\n'

	catch err
		error err
	
	prompt()

		#if not shell.blockingProc
		#	shell.setPrompt prompt()
		


		#if typeof returnValue is 'function' then returnValue()
		#ACCESSOR  = /^([\w\.]+)(?:\.(\w*))$/
		#SIMPLEVAR = /^(\w+)$/i
		#if code.match(ACCESSOR)? or code.match(SIMPLEVAR)? 
		#	builtin.echo returnValue



#Load binaries and built-in shell commands
binaries = {}
for pathname in (process.env.PATH.split ':')
	if path.existsSync(pathname) 
		binaries[file] = pathname for file in fs.readdirSync(pathname)

builtin = 
	pwd: -> process.cwd.apply(this,arguments)
	cd: -> process.chdir.apply(this,arguments)
	echo: (vals...) ->
		for v in vals
			console.log inspect v, true, 5, enableColours
	kill: (pid, signal = "SIGTERM") -> process.kill pid, signal
	which: (val) ->
		if builtin[val]? then console.log 'built-in shell command'.green 
		else if binaries[val]? then console.log "#{binaries[val]}/#{val}".white
		else console.log "command '#{val}'' not found".red


nanoprompt = ->
	proc = spawn 'nano', '',
		cwd: process.cwd()
		env: process.env
		setsid: false
		customFds:[0,1,2]

	proc.on 'exit', ->
		prompt()

	process.stdin.pause()
	proc.stdin.resume()




## Autocompletion

# Regexes to match complete-able bits of text.
ACCESSOR  = /.*([\w\.]+)(?:\.(\w*))$/
SIMPLEVAR = /(\w+)$/i

# Returns a list of completions, and the completed text.
autocomplete = (text) ->
	text = text.substr 0, shell.cursor
	text = text.split(' ').pop()
	completeFile(text) or completeAttribute(text) or completeAttribute(text) or completeVariable(text) or [[], text]

# Attempt to autocomplete a valid file or directory
completeFile = (text) ->
	isdir = text is "" or text[text.length-1] is '/'
	dir = path.resolve text, (if isdir then '.' else '..')
	prefix = if isdir then '' else path.basename text
	if path.existsSync dir then listing = fs.readdirSync dir
	else listing = fs.readdirSync '.'
	completions = (el for el in listing when el.indexOf(prefix) is 0)
	#builtin.echo el for el in first
	#completions = []
	#for el in first
	#	if fs.lstatSync(+'/'+el).isDirectory()
	#		completions.push el+"/"
	#builtin.echo el for el in completions

	if completions.length > 0
		([completions, prefix])

completeBinaries = (text) ->
	completions = getCompletions text, binaries
	[completions, text]

# Attempt to autocomplete a chained dotted attribute: `one.two.three`.
completeAttribute = (text) ->
	if match = text.match ACCESSOR
		[all, obj, prefix] = match
		try
			val = vm.runInContext obj, sandbox
		catch error
			return
		completions = getCompletions prefix, Object.getOwnPropertyNames Object val
		[completions, prefix]

# Attempt to autocomplete an in-scope free variable: `one`.
completeVariable = (text) ->
	free = text.match(SIMPLEVAR)?[1]
	free = "" if text is ""
	if free?
		vars = vm.runInContext 'Object.getOwnPropertyNames(Object(this))', sandbox
		keywords = (r for r in coffee.RESERVED when r[..1] isnt '__')
		possibilities = vars.concat keywords
		completions = getCompletions free, possibilities
		[completions, free]

# Return elements of candidates for which `prefix` is a prefix.
getCompletions = (prefix, candidates) ->
	(el for el in candidates when el.indexOf(prefix) is 0)




camelcase = (flag) ->
	flag.split('-').reduce (str, word) ->
		str + word[0].toUpperCase() + word.slice(1) 
	
parseBool = (str) ->
	/^y|yes|ok|true$/i.test str

padstring = (str, width) ->
	len = Math.max(0, width - str.length)
	str + [len + 1].join(' ')


root.sandbox = sandbox = vm.createContext(root)
[sandbox.require, sandbox.module] = [require, module]
[sandbox.coffee, sandbox.inspect, sandbox.fs, sandbox.path, sandbox.spawn, sandbox.colors, sandbox.Lexer] = [coffee, inspect, fs, path, spawn, colors, Lexer]
[sandbox.builtin, sandbox.binaries, sandbox.shell] = [builtin, binaries, shell]
sandbox.global = sandbox.GLOBAL = sandbox.root = sandbox





#nonContextGlobals = [
#	'Buffer', 'console', 'process'
#	'setInterval', 'clearInterval'
#	'setTimeout', 'clearTimeout'
#]
#	'inspect', 'fs', 'path', 'require']
#	'coffee', 'helpers',, #
#	'Script','Module','fs','path',
##'spawn','colors','Lexer'

#sandbox[g] = global[g] for g in nonContextGlobals



#process.stdin.resume()

	# # Create the shell by listening to **stdin**.
	# shell = readline.createInterface process.stdin, process.stdout, autocomplete	
	

			
	# binaries['nano'] = (args...) ->
	# 	shell.input.pause()
	# 	shell.pause()
	# 	shell.blockingProc = true
	# 	#shell.removeAllListeners()
	# 	#process.stdin.removeAllListeners()

		
		
		

	
	
	# 		#binaries[file] = (args...) ->
	# 				#shell.blockingProc = yes
	# 				# proc = spawn pathname + "/" + file, args, {
	# 				# 	cwd: process.cwd()
	# 				# 	env: process.env
	# 				# 	setsid: false
	# 				# }
	# # 				proc.stdout.on 'data', (data) -> process.stdout.write(data)
	# # 				proc.stderr.on 'data', (data) -> process.stderr.write(data)
	# # 				
	# #shell.output.cursorTo(shelllength)
	# #root.binaries = binaries



	# shell.backlog = ''
	# shell.multilineMode = off
	# shell.blockingProc = off

	# shell.on 'SIGINT', ->
	# 	return if shell.blockingProc
	# 	shell.backlog = ''
	# 	shell.multilineMode = off
	# 	shell.historyIndex = -1
	# 	shell.output.write '\n'
	# 	shell.line = ''
	# 	shell.setPrompt prompt()
	# 	prompt()
	# 	#shell.output.cursorTo(shelllength)

	# shell.on 'attemptClose', ->
	# 	if shell.backlog
	# 		shell.backlog = ''
	# 		process.stdout.write '\n'
	# 		shell.setPrompt prompt
	# 		prompt()
	# 	else
	# 		shell.close()

	# shell.on 'close', ->
	# 	fs.closeSync shell.history_fd
	# 	shell.output.write '\n'
	# 	shell.input.destroy()

	# shell.on 'line', runline

	# shell.setPrompt prompt()
	# prompt()
