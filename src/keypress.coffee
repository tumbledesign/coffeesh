{dirname,basename,extname,exists,existsSync} = path = require('path')
{helpers:{starts,ends,compact,count,merge,extend,flatten,del,last}} = coffee = require 'coffee-script'
{inspect,print,format,puts,debug,log,isArray,isRegExp,isDate,isError} = util = require 'util'
[os,tty,vm,fs,colors] = [require('os'), require('tty'), require('vm'), require('fs'), require('./colors')]

module.exports =
	keypress: (s, key) ->
	
		#We need to handle mouse events, they are not provided by node's tty.js
		if not key? and (s.indexOf("\u001b[M") is 0)
			
			modifier = s.charCodeAt(3)
			key ?= shift: !!(modifier & 4), meta: !!(modifier & 8), ctrl: !!(modifier & 16)
			[@mousex, @mousey] = [s.charCodeAt(4) - 33, s.charCodeAt(5) - 33]
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
			#if key.name? then return

		key ?= {}

		# enter
		if s is '\r'
			if @cy > 0 and @cLines[@cLines.length-1] is ''
				@cLines.pop()
				@cy--
				@runline()
				return
			
			#if @cx 0 and @cy is 0 and @cLines[0].length is 0
			#	return
			
			@cLines[++@cy] = ''
			for char in @cLines[@cy-1]
				unless char is "\t" then break
				@cLines[@cy] += "\t"
			@cx = @cLines[@cy].length
			@redrawPrompt()
			return
			
		# ctrl enter
		else if s is '\n'
			@runline()
			return
			
		keytoken = [if key.ctrl then "C^"] + [if key.meta then "M^"] + [if key.shift then "S^"] + [if key.name then key.name] + ""		

	 
		switch keytoken
				
			# SIGINT
			# TODO: fix
			when "C^c"
				@pause()
				@resume()
				@redrawPrompt()		
				
			# Background
			when "C^z" 
				return process.kill process.pid, "SIGTSTP"
			
			# Logout
			when "C^d"
				@close() if @cx is 0 and @cLines[@cy].length is 0 and @cLines.length is 1

			when "tab" 
					
				if @cx is 0 or @cLines[@cy][@cx-1] is "\t"
					@cLines[@cy] =  "\t" + @cLines[@cy][0...@cLines[@cy].length]
					@cx++
					@redrawPrompt()
				else
					@tabcomplete()
			
			when "S^tab"
				if @cx > 0 and @cLines[@cy][@cx-1] is "\t"
					@cx--
					@cLines[@cy] = @cLines[@cy][0...@cx] + @cLines[@cy][@cx+1..]
					@redrawPrompt()
				else
					@tabcomplete()
			#when "enter" then @runline()

			# Clear line
			when "C^u"
				@cLines[@cy] = ''
				@cx = 0
				@redrawPrompt()

		## Deletions

			when "backspace", "C^h"
				if @cx > 0 and @cLines[@cy].length > 0
					@cx--
					@cLines[@cy] = @cLines[@cy][0...@cx] + @cLines[@cy][@cx+1..]
					
					@redrawPrompt()
					
				else if @cy isnt 0 and @cy is (+@cLines.length-1) and @cLines[@cy].length is 0
					@cy--
					@cLines.pop()
					@cx = @cLines[@cy].length
					@redrawPrompt()

				# else if @cy is 0 and @cx is 0  and @cLines[0].length is 0
				# 	@cLines = ['']
					
			when "delete", "C^d"
				if @cx < @cLines[@cy].length
					@cLines[@cy] = @cLines[@cy][0...@cx] + @cLines[@cy][@cx+1...]
					@redrawPrompt()
					
			# Word left
			when "C^w", "C^backspace", "M^backspace"
				if @cx > 0
					leading = @cLines[@cy][0...@cx]
					match = leading.match(/// \S*\s* $ ///)
					leading = leading[0...(leading.length - match[0].length)]
					@cLines[@cy] = leading + @cLines[@cy][@cx...@cLines[@cy].length]
					@cx = leading.length
					@redrawPrompt()
					
				# else if @cy is 0 and @cx is 0 and @cLines[0].length is 0
				# 	@cLines = ['']
				# 	@redrawPrompt()
					
					
			# Word right
			when "C^delete", "M^d", "M^delete"
				if @cx < @cLines[@cy].length
					trailing = @cLines[@cy][@cx...]
					match = trailing.match(/// ^ \s*\S+ ///)
					@cx = @cLines[@cy].length - trailing.length
					@cLines[@cy] = trailing + @cLines[0..@cx][@cx+1...].length
					@redrawPrompt()
					
					#if @cy is 0 and @cx is 0 and @cLines is []
					#	@cLines = ['']
			# Line right
			when "C^k", "C^S^delete"
				@cLines[@cy] = @cLines[@cy][0...@cx]
				@redrawPrompt()
			# Line left
			when "C^S^backspace", "M^S^d"
				@cLines[@cy] = @cLines[@cy][@cx...]
				@cx = 0
				@redrawPrompt()
				
		## Cursor Movements

			when "home", "C^a"
				@cx = 0
				@redrawPrompt()
			when "end", "C^e"
				@cx = @cLines[@cy].length
				@redrawPrompt()
			when "left", "C^b"
				if @cx > 0
					@cx--
					@redrawPrompt()
			when "right", "C^f"
				unless @cx is @cLines[@cy].length
					@cx++
					@redrawPrompt()
			# Word left
			when "C^left", "M^b"
				if @cx > 0
					leading = @cLines[@cy][0...@cx]
					match = leading.match(/// \S*\s* $ ///)
					@cx -= match[0].length
					@redrawPrompt()
			# Word right
			when "C^right", "M^f"
				if @cx < @cLines[@cy].length
					trailing = @cLines[@cy][@cx...]
					match = trailing.match(/// ^ \s*\S+ ///)
					@cx += match[0].length
					@redrawPrompt()


			## History
			when "up", "C^p", "down", "C^n"
				
				if keytoken in ['up', 'C^p'] and @cy > 0
					@cy--
					@cx = Math.min @cx, @cLines[@cy].length
					@redrawPrompt()
					return
					
				else if keytoken in ['down', 'C^n'] and 0 <= @cy < @cLines.length-1
					@cy++
					@cx = Math.min @cx, @cLines[@cy].length
					@redrawPrompt()
					return				
					
				if @historyIndex is -1 and keytoken in ['up', 'C^p']
					@displayDebug @cLines
					@historyIndex = 0
					@tmp_history = @cLines

				else if @historyIndex is 0 and keytoken in ['down', 'C^n']
					@historyIndex = -1
					[@cLines, @cx, @cy] = [@tmp_history, @tmp_history[0].length, 0]
					@redrawPrompt()
					return

				else if @historyIndex + 1 < @history.length and keytoken in ['up', 'C^p']
					@historyIndex++
					
				else if @historyIndex > 0 and keytoken in ['down', 'C^n']
					@historyIndex--

				else return
				

				@cLines = (@history[@historyIndex]).split('\n')
				@displayDebug [@historyIndex, (@history[@historyIndex]), (@history[@historyIndex]).split('\n')]
				@cy = @cLines.length - 1
				@cy = 0 if keytoken in ['down', 'C^n']
				@cx = @cLines[@cy].length
				@displayDebug [@cLines, @cy, @cx]
				@redrawPrompt()

				
		# Scrolling
			when "pageup"
				@scrollUp(@promptRow - 2)

			when "pagedown"
				@scrollDown(@promptRow - 2)

			when "scrollup"
				@scrollUp(1)

			when "scrolldown"
				@scrollDown(1)

		## Mouse stuff
			# when 'mousedownL' then
			# when 'mousedownM' then
			# # Right click is captured by gnome-terminal, but C^rightclick and S^rightclick are available
			# when 'C^mousedownR' then
			# when 'mouseup' then
			# when 'mousemove' then
			# when 'scrolldown' then
			# when 'scrollup'
				


			else
				return if keytoken.indexOf('scroll') isnt -1 or keytoken.indexOf('mouse') isnt -1
				s = s.toString("utf-8") if Buffer.isBuffer(s)
				beg = @cLines[@cy][0...@cx]
				end = @cLines[@cy][@cx...@cLines[@cy].length]
				@cLines[@cy] = beg + s + end
				@cx += s.length
				@redrawPrompt()
