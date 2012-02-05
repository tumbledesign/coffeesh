colors = require './colors'

module.exports =
	'ttymgr': ->
	# Command Prompt Area
		@STATUSBAR = (width = 80) -> "                                   Coffeeshell                                    ".bgblack.red
		@PROMPT = => return "#{@HOSTNAME.white}:#{@cwd.blue.bold} #{if @user is 'root' then '➜'.red else '➜'.green}"
		@MULTIPROMPT = => return "➜ ".green
		@TABSTOP = 2
		@PROMPTHEIGHT = 6
		
		
		@cx = @cy = 0
		@cTabs = [0]
		@cLines = ['']
		
		
		#@MOUSETRACK = "\x1b[?1003h\x1b[?1005h"
		#@MOUSEUNTRACK = "\x1b[?1003l\x1b[?1005l"
		
		
		[@numcolumns, @numrows] = @output.getWindowSize()
		if @STATUSBAR then @numrows--

		process.on "SIGWINCH", => 
			[@numcolumns, @numrows] = @output.getWindowSize()
			if @STATUSBAR then @numrows--
		@buffer = []
		for r in [1..@numrows]
			line = ""
			for c in [1..@numcols]
				line += " "
			@buffer.push line
		@promptRow = 1
		@topRow = 1
		@scrollOffset = 0
		[@row, @col] = [1, 1]


	# We're using 1-based array
	cursorTo: (col,row) -> @output.cursorTo col+1, row+1

	reDraw: ->
		@cursorTo 0, 0
		for r in [1...@numrows]
			if @buffer.length <= r
				@output.clearLine(0)
			else
				@output.write @buffer[@topRow - @scrollOffset + r]
		@cursorTo @col, @row

	redrawPrompt: ->
		for y,l of @cLines
			@output.cursorTo 0, (@numrows -  @PROMPTHEIGHT) + y
			@output.clearLine 0
			if y is 0
				@PROMPT()
				@output.write @PROMPT() + @cLines[y].length
				@output.cursorTo p.removeStyle.length + @cLines[y].length
					
			else if y > 0
				p = @MULTIPROMPT()
				for t in @cTabs[y]
					p+='|'
					p += '·' for i in [0...@TABSTOP]
			
				@output.cursorTo p[y].length + @cLines[y].length
			@output.cursorTo(@cx,@cy)
				
	scrollDown: (n = 1) ->
	
		return if n < 1

		return if (@buffer.length <= @numrows) or (@topRow is @numrows)
		if @topRow - @scrollOffset is 1 then return
		else if (@topRow - @scrollOffset) + n < 1 then n = (@scrollOffset - @topRow) + 1
		@topRow -= n
		@scrollOffset += n
		@reDraw()

	scrollUp: (n = 1) ->
		return if n < 1 

		if @topRow - @scrollOffset is 1 then return
		else if (@topRow - @scrollOffset) + n < 1 then n = (@scrollOffset - @topRow) + 1
		@topRow -= n
		@scrollOffset += n
		@reDraw()


	clearLine: -> 
		emptyline = ""
		emptyline += " " for i in [1..@numcols]
		@buffer[@absRow] = emptyline
		@output.clearLine(0)

	newLine: ->
		return if @row isnt @buffer.length

		newrow = ""
		newrow += " " for i in [1..@numcols]
		@buffer.push newrow

		if @row is @numrows
			@scrollDown()
		else @row++
		@col = 1
		@output.write "\r\n"

	write: (str) ->
		# TODO: handle \r, \n, \t, \v, \b
		for c in str
			@buffer[@row][@col] = c
			if @col is @numcols
				@col = 1
				@newLine()
			else @col++
			@output.write c