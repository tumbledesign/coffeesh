colors = require './colors'
fs = require 'fs'
inspect = require('util').inspect

module.exports =
	'ttymgr': ->

		@PROMPT = "» "
		@TABSTOP = 2
		@MINPROMPTHEIGHT = 6
		@CMD_BACKGROUND = 'magenta'
		@CMD_TEXT = 'blue'
		@OUTPUT_BACKGROUND = 'black'
		@OUTPUT_TEXT = 'green'
		
		
		@cx = @cy = 0
		@cTabs = [0]
		@cLines = ['']

		[@numcols, @numrows] = @output.getWindowSize()
		@buffer = []
		@__defineGetter__ "promptRow", => (@numrows - Math.max(@MINPROMPTHEIGHT, @cLines.length)) 
		@scrollOffset = 0
		[@col, @row] = [0, 0]

		process.on "SIGWINCH", => 
			[@numcols, @numrows] = @output.getWindowSize()
			@drawShell()

	mouseTracking: (e = on) ->
		if e then @output.write "\x1b[?1003h\x1b[?1005h"
		else @output.write "\x1b[?1003l\x1b[?1005l"

	drawShell: ->
		@output.cursorTo 0, 0
		@output.write colors.reset
		@output.write colors["bg"+@OUTPUT_BACKGROUND]
		for r in [0..@promptRow]
			@output.cursorTo 0, r
			@output.clearLine(0)
		@redrawOutput()
		@redrawPrompt()


	redrawPrompt: ->
		@output.cursorTo 0, @promptRow
		@output.write colors["bg"+@CMD_BACKGROUND]
		#clear all of console
		for i in [@promptRow...@numrows]
			@output.cursorTo 0, i
			@output.clearLine 0

		for y,l of @cLines
			y = +y
			@output.cursorTo 0, @promptRow + y
			@output.clearLine 0
			p = "#{if @user is 'root' then @PROMPT.red else @PROMPT.green}"
			for t in [0...@cTabs[y]]
				p +='|'
				p += '·' for i in [0...@TABSTOP]
			@output.write p + l[@CMD_TEXT]

		@output.cursorTo(@PROMPT.length + @cTabs[@cy] * [@TABSTOP+1] +  @cx, @promptRow + @cy)

		#@output.write colors.reset
		
		
	redrawOutput: ->
		@output.cursorTo 0, 0
		@output.write colors["bg"+@OUTPUT_BACKGROUND]
		for r in [0...@promptRow]
			@output.cursorTo 0, r
			@output.clearLine(0)
			if r + @scrollOffset < @buffer.length
				@output.cursorTo 0, r
				@output.write @buffer[r + @scrollOffset][...@numcols].replace(/\u001b\[39m/g,colors[@OUTPUT_TEXT]).replace(/\u001b\[49m/g,colors["bg"+@OUTPUT_BACKGROUND])
				@output.write "…" if @buffer[r + @scrollOffset].length > @numcols


		@output.cursorTo(@PROMPT.length + @cx, @promptRow + @cy)


			
	scrollDown: (n) ->
		return if n? and n < 1

		# Can't scroll down if not enough lines have been output
		return if @buffer.length < @promptRow

		# Scroll to bottom
		if not n? or @buffer.length - (@scrollOffset + n) <= @promptRow
			@scrollOffset = Math.max(0, @buffer.length - @promptRow)

		# Scroll n lines
		else
			@scrollOffset += n

		@redrawOutput()

	scrollUp: (n) ->
		return if n? and n < 1

		# Can't scroll up if not enough lines have been output
		return if @buffer.length < @promptRow

		#Scroll to top
		if not n? or @scrollOffset - n <= 0
			@scrollOffset = 0

		else
			@scrollOffset -= n

		@redrawOutput()

	displayDebug: (debug) ->
		fs.write  @debuglog, debug+"\n\n---------------------------------------\n\n"

	displayError: (err) ->
		if typeof err isnt 'string'
			err = inspect(err, true, 2, true)
		@output.cursorTo 0, @row
		@output.write colors["bg"+@OUTPUT_BACKGROUND] or colors.bgdefault
		@output.write colors.red
		@displayBuffer "ERROR"

		@redrawPrompt()
		fs.write @errlog, err+"\n\n---------------------------------------\n\n"

	displayOutput: (data) ->
		if typeof data isnt 'string'
			data = inspect(data, true, 2, true)
		@output.cursorTo 0, @row

		@displayBuffer data["bg"+@OUTPUT_BACKGROUND][@OUTPUT_TEXT]
		
		
		#@output.write colors.reset

		@output.cursorTo(@PROMPT.length + @cx, @promptRow + @cy)
		fs.write @outlog, data+"\n\n---------------------------------------\n\n"

	displayInput: (data) ->
		@output.cursorTo 0, @row
		
		@redrawPrompt()

		@displayDebug data
		@displayBuffer data["bg"+@OUTPUT_BACKGROUND][@OUTPUT_TEXT].bold
		#@output.write colors.reset

		fs.write @inlog, data+"\n\n---------------------------------------\n\n"

	displayBuffer: (str) ->
		numbuffered = 0
		lines = str.split(/\r\n|\n|\r/)

		for line in lines
			while line.length > 0
				@buffer.push line[...@numcols]
				line = line[@numcols...]
				numbuffered++

		@row += numbuffered

		if @row > @promptRow
			@scrollDown()
		else
			@redrawOutput()

		
		