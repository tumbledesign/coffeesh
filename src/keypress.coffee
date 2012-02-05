{dirname,basename,extname,exists,existsSync} = path = require('path')
{helpers:{starts,ends,compact,count,merge,extend,flatten,del,last}} = coffee = require 'coffee-script'
{inspect,print,format,puts,debug,log,isArray,isRegExp,isDate,isError} = util = require 'util'
[os,tty,vm,fs,colors] = [require('os'), require('tty'), require('vm'), require('fs'), require('colors')]

module.exports =
	keypress: (s, key) ->
	
		#We need to handle mouse events, they are not provided by node's tty.js
		#		if not key? and (s.indexOf("\u001b[M") is 0)
		#			
		#			modifier = s.charCodeAt(3)
		#			key ?= shift: !!(modifier & 4), meta: !!(modifier & 8), ctrl: !!(modifier & 16)
		#			[@_mouse.x, @_mouse.y] = [s.charCodeAt(4) - 33, s.charCodeAt(5) - 33]
		#			if ((modifier & 96) is 96)
		#				key.name ?= if modifier & 1 then 'scrolldown' else 'scrollup'
		#			else if modifier & 64 then key.name ?= 'mousemove'
		#			else
		#				switch (modifier & 3)
		#					when 0 then key.name ?= 'mousedownL'
		#					when 1 then key.name ?= 'mousedownM'
		#					when 2 then key.name ?= 'mousedownR'
		#					when 3 then key.name ?= 'mouseup'
		#					#else return
		#			#Disable mouse events for now
		#			if key.name? then return

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
			@_tabs[@_cursor.y] = 0
			@_cursor.x = 0
			@_prompt =  @PROMPT()
			@output.cursorTo 0
			@output.clearLine 0
			@output.write @_prompt + @_lines[@_cursor.y]
			@output.cursorTo @_prompt.stripColors.length + @_cursor.x
			return
			
		keytoken = [if key.ctrl then "C^"] + [if key.meta then "M^"] + [if key.shift then "S^"] + [if key.name then key.name] + ""

		switch keytoken
		
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
					@_tabs[@_cursor.y]++
					@_prompt = @PROMPT()
					
					@output.cursorTo 0
					@output.clearLine 0
					@output.write @_prompt
					@output.cursorTo @_prompt.stripColors.length
				else
					@tabcomplete()
			
			when "S^tab"
				if @_cursor.x is 0
					if @_tabs[@_cursor.y] > 0
						@_tabs[@_cursor.y]--
					
					@_prompt = @PROMPT()
					@output.cursorTo 0
					@output.clearLine 0
					@output.write @_prompt
					@output.cursorTo @_prompt.stripColors.length
				else
					@tabcomplete()
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
					@_prompt = @PROMPT()
					
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
					@_prompt = @PROMPT()
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
					
					@_prompt = @PROMPT()
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
					@_prompt = @PROMPT()
					@_cursor.x = @_lines[@_cursor.y].length
					@output.cursorTo @_prompt.stripColors.length + @_cursor.x
					return
					
				else if keytoken in ['down', 'C^n'] and @_cursor.y < @_lines.length-1 and @_cursor.y >= 0 and @_lines.length > 0
					@_cursor.y++
					@output.moveCursor 0, 1
					@_prompt = @PROMPT()
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
					match = @_lines[i].match(/// ^ ([\t]*)([^\t]*) ///)
					@_tabs[i] = match[1].split('\t').length-1
					@_lines[i] = match[2]
					@_cursor.y = i
					@_cursor.x = @_lines[@_cursor.y].length
					@_prompt = @PROMPT()
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
					#			when 'mousedownL' then
					#			when 'mousedownM' then
					#			# Right click is captured by gnome-terminal, but C^rightclick and S^rightclick are available
					#			when 'C^mousedownR' then
					#			when 'mouseup' then
					#			when 'mousemove' then
					#			when 'scrolldown' then
					#			when 'scrollup'
					## Directly output char to terminal