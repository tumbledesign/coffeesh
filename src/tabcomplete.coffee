{helpers:{starts,ends,compact,count,merge,extend,flatten,del,last}} = coffee = require 'coffee-script'
{inspect,print,format,puts,debug,log,isArray,isRegExp,isDate,isError} = util = require 'util'
{dirname,basename,extname,exists,existsSync} = path = require('path')
[os,tty,vm,fs,colors] = [require('os'), require('tty'), require('vm'), require('fs'), require('./colors')]
require 'fibers'
module.exports = 

	tabcomplete: ->
		[' ','(','[','{',"'",'"','>','<','&','|',':']
		pieces = @cLines[@cy][0...@cx]
		@autocomplete (@_lines[@_cursor.y][0...@_cursor.x]).split(' ').pop(), (completions, completeOn) =>
			if completions and completions.length
				if completions.length is 1
					@insertString completions[0].slice(completeOn.length)
					return
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
