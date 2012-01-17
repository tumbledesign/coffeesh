# Coffeescript Shell
#
#
#

# Start by opening up `stdin` and `stdout`.
stdin = process.openStdin()
stdout = process.stdout

global.CoffeeScript = require 'coffee-script'
readline     = require 'readline'
{inspect}    = require 'util'
{Script}     = require 'vm'
Module       = require 'module'
fs           = require 'fs'
path         = require 'path'
spawn        = require('child_process').spawn
{flatten, starts, del, ends, last, count, merge, compact, extend} = require('coffee-script').helpers
colors       = require 'colors'
blockingProc = no

#coffee = require './coffee-script'
{Lexer} = require './lexer'
#root.Lexer = Lexer
#{Rewriter} = require './rewriter'
#{parser} = require './grammar'




# Load built-in shell commands
global.builtin =
	pwd: process.cwd
	echo: (val, showhidden = no, depth = 3, colors = yes) ->
		console.log inspect val, showhidden, depth, colors
	kill: (pid, signal = "SIGTERM") -> process.kill pid, signal
	which: (val) ->
		if builtin[val]? then console.log 'built-in shell command'.green ; return
		###
		for pathname in process.env.PATH.split ':'
			if path.existsSync pathname
				for file in fs.readdirSync pathname
					if file is val then console.log pathname.white ; return
		###
		console.log "command '#{val}'' not found".red
	cd: (dir) -> process.chdir(dir)

# Load all executables from PATH
global.binaries = []

for pathname in process.env.PATH.split ':'
	if path.existsSync pathname then do (pathname) ->
		for file in fs.readdirSync pathname then do (file) ->
			global.binaries[file] ?= (args...) ->
				blockingProc = yes
				proc = spawn pathname + "/" + file, args, {
					cwd: process.cwd()
					env: process.env
					setsid: false
				}
				proc.stdout.on 'data', (data) -> process.stdout.write(data)
				proc.stderr.on 'data', (data) -> process.stderr.write(data)
				proc.on 'exit', ->
					blockingProc = no
					shell.setPrompt SHELL_PROMPT()
					shell.prompt()
					#shell.output.cursorTo(shelllength)

# Export environment vars to the global namespace
global.env = process.env

# Config
#shelllength = 2
SHELL_PROMPT = -> 
	u = process.env.USER
	d = process.cwd() #.replace('/home/'+u,'~')
	#shelllength = "#{u}:#{d}$ ".length
	("#{u}:#{d}$ ")

SHELL_PROMPT_CONTINUATION = '......> '
SHELL_HISTORY_FILE = process.env.HOME + '/.coffee_history'

enableColours = no
unless process.platform is 'win32'
	enableColours = not process.env.NODE_DISABLE_COLORS

# Log an error.
error = (err) ->
	stdout.write (err.stack or err.toString()) + '\n'

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
			val = Script.runInThisContext obj
		catch error
			return
		completions = getCompletions prefix, Object.getOwnPropertyNames Object val
		[completions, prefix]

# Attempt to autocomplete an in-scope free variable: `one`.
completeVariable = (text) ->
	free = text.match(SIMPLEVAR)?[1]
	free = "" if text is ""
	if free?
		vars = Script.runInThisContext 'Object.getOwnPropertyNames(Object(this))'
		keywords = (r for r in CoffeeScript.RESERVED when r[..1] isnt '__')
		possibilities = vars.concat keywords
		completions = getCompletions free, possibilities
		[completions, free]

# Return elements of candidates for which `prefix` is a prefix.
getCompletions = (prefix, candidates) ->
	(el for el in candidates when el.indexOf(prefix) is 0)

# Helper function for gathering quoted goods
get_piece = (piece, stack, oldpieces, pieces) ->
	oldpieces.push (piece)
	for i,char of piece
		if char is '\\' and char[i+1]? in ["'", '"'] then i++
		else if char in ["'", '"']
			if char is last(stack)
				stack.pop()
				return if stack.length is 0
			else stack.push char
	if stack.length isnt 0 
		get_piece pieces.shift(), stack, oldpieces, pieces


# Create the shell by listening to **stdin**.
if readline.createInterface.length < 3
	shell = readline.createInterface stdin, autocomplete
	stdin.on 'data', (buffer) -> shell.write buffer
else
	shell = readline.createInterface stdin, stdout, autocomplete


# load history
shell.history = fs.readFileSync(SHELL_HISTORY_FILE, 'utf-8').split('\n').reverse()
shell.history.shift()
shell.historyIndex = -1
history_fd = fs.openSync SHELL_HISTORY_FILE, 'a+', '644'

# Make sure that uncaught exceptions don't kill the shell.
process.on 'uncaughtException', ->
	error
	#shell.output.cursorTo(shelllength)

# The current backlog of multi-line code.
backlog = ''

multilineMode = off

shell.on 'SIGINT', ->
	backlog = ''
	multilineMode = off
	shell.historyIndex = -1
	shell.output.write '\n'
	shell.line = ''
	shell.setPrompt SHELL_PROMPT()
	shell.prompt()
	#shell.output.cursorTo(shelllength)

shell.on 'close', ->
	fs.closeSync history_fd
	shell.output.write '\n'
	shell.input.destroy()

shell.on 'line', (buffer) ->
	
	if !buffer.toString().trim() and !backlog
		shell.prompt()
		return
	code = backlog += buffer
	if code[code.length - 1] is '\\'
		backlog = "#{backlog[...-1]}\n"
		shell.setPrompt SHELL_PROMPT_CONTINUATION
		shell.prompt()
		return
	

	tokens = (new Lexer).tokenize(code, {rewrite: on})
	console.log tokens
	root.tokens = tokens
	root.mkstr = Lexer.prototype.makeString
	backlog = ''
	#output = [] ; args = [] ; cmd = ''
	#pieces = code.split ' '
	shell.setPrompt SHELL_PROMPT()
	shell.prompt()

	output = []
	tmp = ''
	call_started = false
	index_started = false
	dot_started = false
	cmd = ''
	args = []
	nested = []

	for i in [0...tokens.length]
		lex = tokens[i][0]
		val = tokens[i][1]
		

		builtin.echo [lex, val]

		if lex in ['.']
			dot_started = true
			output.push '['

		else if lex in ['INDEX_START', '[']
			index_started = true
			output.push '['
		
		else if lex in ['INDEX_END', ']']
			index_started = false
			output.push ']'

		else if lex in ['CALL_START']
			if !call_started
				call_started = true
				output.push '('
				tmp = output.join('')
				output = []
			#else
			#	output.push ','

		else if lex in ['CALL_END']
			if call_started
				call_started = false
				tmp2 = output.join(', ')
				output = [tmp, tmp2, ')']
				#output.push ')'
		else
			if lex in ['IDENTIFIER', 'STRING']
				if builtin[val]?
					output.push "builtin[\"#{val}\"]"
				else if binaries[val]?
					output.push "binaries[\"#{val}\"]"
				else if global[val]?
					output.push "#{val}"
				else
					output.push "\"#{val}\""

			else if lex in ['FILEPATH'] and path.existsSync(val)
				output.push "#{val}"

			else
				output.push "#{val}"

				
			#if tokens[i].spaced then output.push ' '

			if index_started 
				output +=']'
				index_started = false
			if dot_started
				output +=']'
				dot_started = false
			##if call_started
			#	output += ', '
		
		builtin.echo output



	###
	while piece = pieces.shift()
		if -1 in [piece.indexOf('"'), piece.indexOf("'")]
			stack = []
			oldpieces=[]
			get_piece piece, stack, oldpieces, pieces
			piece = oldpieces.join " "
		
		# TODO: see if if() works
		if piece in CoffeeScript.RESERVED
			if cmd isnt ''
				output.push "#{cmd} [#{args}]" #"CoffeeScript.eval \"#{eval_line}\""
				cmd = '' ; args = []
			output.push piece
			continue
		if cmd is ''
			if builtin[piece]?
				cmd = "builtin['#{piece}'].apply this,"
			else if binaries[piece]?
				cmd = "binaries['#{piece}']"
			else if global[piece]?
				if typeof piece is 'function'
					cmd = "#{piece}.apply this,"
				else output.push piece
			else
				output.push piece
		else if piece[0] is '-' or (path.existsSync(piece)) or not CoffeeScript.eval("#{piece}?")
			args.push "'#{piece}'"
		else
			args.push piece
	if cmd isnt '' then output.push "#{cmd} [#{args}]" #"CoffeeScript.eval \"#{eval_line}\""
	code = output.join ' '
	###

	code = output.join ''
	console.log code
	try
		_ = global._
		returnValue = CoffeeScript.eval "_=(#{code}\n)" #, filename: __filename, modulename: 'shell'
		#console.log returnValue

		if typeof returnValue is 'function' then returnValue()
		global._ = _ if returnValue is undefined
		ACCESSOR  = /^([\w\.]+)(?:\.(\w*))$/
		SIMPLEVAR = /^(\w+)$/i
		if code.match(ACCESSOR)? or code.match(SIMPLEVAR)? 
			builtin.echo returnValue
		fs.write history_fd, code + '\n'
	catch err
		error err
	if not blockingProc
		shell.setPrompt SHELL_PROMPT()
		shell.prompt()
		#shell.output.cursorTo(shelllength)

exports.run = ->
	shell.setPrompt SHELL_PROMPT()
	shell.prompt()
	#shell.output.cursorTo(shell.cursor)
