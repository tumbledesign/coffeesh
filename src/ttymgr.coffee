colors = require './colors'
fs = require 'fs'

module.exports =
	'ttymgr': ->
	# Command Prompt Area

		# user can override this with a function or set to "off" to disable
		#@STATUSBAR = (width = 80) => "custom status ..."
		@PROMPT = => "#{if @user is 'root' then '➜'.red else '➜'.green} "
		@TABSTOP = 2
		@MINPROMPTHEIGHT = 6
		@CMD_BACKGROUND = 'gray'
		@OUTPUT_BACKGROUND = 'default'
		
		@cx = @cy = 0
		@cTabs = [0]
		@cLines = ['']
		
		
		[@numcols, @numrows] = @output.getWindowSize()
		@numrows-- unless @STATUSBAR is off

		process.on "SIGWINCH", => 
			[@numcols, @numrows] = @output.getWindowSize()
			@numrows-- unless @STATUSBAR is off

		# TODO: likely don't need to fill buffer with blanks. try removing when get a chance
		@buffer = []
		for r in [0...@numrows]
			line = ""
			line += " " for c in [0...@numcols]
			@buffer.push line

		# TODO: change to definegetter
		@promptRow = => (@numrows - Math.max(@MINPROMPTHEIGHT, @cLines.length)) 
		
		@scrollOffset = 0
		[@col, @row] = [0, 0]

	# When I'm done stealing the cursor to write output, replace it to the prompt
	replaceCursor: -> @output.cursorTo((@PROMPT().removeStyle).length + @cx, @promptRow() + @cy)

	mouseTracking: (e = on) ->
		if e then @output.write "\x1b[?1003h\x1b[?1005h"
		else @output.write "\x1b[?1003l\x1b[?1005l"

	drawShell: ->
		@output.cursorTo 0, 0
		@output.write colors.reset
		for r in [0..@promptRow()]
			@output.cursorTo 0, r
			@output.clearLine(0)
		@redrawStatus() unless @STATUSBAR is off
		@redrawPrompt()


	redrawStatus: ->
		if @STATUSBAR is off then return
		
		if @STATUSBAR?()? and @STATUSBAR?().removeStyle.length <= @numcols
			s = @STATUSBAR()
		else if @STATUSBAR?
			s = "custom status invalid"
		else
			d = new Date()
			time = "#{(d.getHours() % 12)}:#{d.getMinutes()}:#{d.getSeconds()}"
			s = "#{colors.bgblack}--#{'Coffeeshell'.red}--#{@HOSTNAME.white}--(#{@cwd.blue.bold})--#{time}--"

		@output.cursorTo 0, @numrows
		@output.write colors.reset
		@output.write s


	redrawPrompt: ->

		@output.cursorTo 0, @promptRow()
		@output.write colors["bg"+@CMD_BACKGROUND] or colors.bgdefault
		#clear all of console
		for i in [@promptRow()...@numrows]
			@output.cursorTo 0, i
			@output.clearLine 0

		for y,l of @cLines
			y = +y
			@output.cursorTo 0, @promptRow() + y
			@output.clearLine 0
			p = @PROMPT()
			for t in [0...@cTabs[y]]
				p +='|'
				p += '·' for i in [0...@TABSTOP]
			@output.write p + l
		@replaceCursor()

	redrawOutput: ->
		@output.cursorTo 0, 0
		@output.write colors.reset
		for r in [0..@promptRow()]
			@output.cursorTo 0, r
			@output.clearLine(0)
			if r + @scrollOffset < @buffer.length
				@output.write @buffer[r + @scrollOffset][..@numcols-1]
				@output.write "…" if @buffer[r + @scrollOffset].length > @numcols

		@replaceCursor()

			
	scrollDown: (n) ->
		return if n? and n < 1

		# Can't scroll down if not enough lines have been output
		return if @buffer.length < @numrows

		# Scroll to bottom
		if not n? or @buffer.length - (@scrollOffset + n) <= @numrows
			@scrollOffset = @buffer.length - @numrows

		# Scroll n lines
		else
			@scrollOffset += n

		@redrawOutput()

	scrollUp: (n) ->
		return if n? and n < 1

		# Can't scroll up if not enough lines have been output
		return if @buffer.length < @numrows

		#Scroll to top
		if not n? or @scrollOffset - n <= 0
			@scrollOffset = 0

		else
			@scrollOffset -= n

		@redrawOutput()

	displayDebug: (debug) ->
		fs.write  @debuglog, debug

	displayError: (err) ->
		@output.cursorTo 0, @row
		@output.write colors["bg"+@OUTPUT_BACKGROUND] or colors.bgdefault
		@output.write colors.red
		@displayBuffer data

		@redrawPrompt()
		fs.write @errlog, err

	displayOutput: (data) ->
		if typeof data isnt 'string'
			data = inspect(data, true, 2, true)
		@output.cursorTo 0, @row
		@output.write colors["bg"+@OUTPUT_BACKGROUND] or colors.bgdefault

		@displayBuffer data

		@output.cursorTo((@PROMPT().removeStyle).length + @cx, @promptRow() + @cy)
		fs.write @outlog, data

	displayInput: (data) ->
		@output.cursorTo 0, @row
		@output.write colors["bg"+@OUTPUT_BACKGROUND] or colors.bgdefault

		@displayDebug data
		@displayBuffer data

		@redrawPrompt()

		fs.write @inlog, data

	displayBuffer: (str) ->
		numbuffered = 0
		lines = str.split(/\r\n|\n|\r/)
		for line in lines
			while line.length > 0
				@buffer.push line[...@numcols]
				line = line[@numcols...]
				numbuffered++

		if @row + numbuffered > @promptRow() - 1
			@scrollDown()

		@row += numbuffered
		