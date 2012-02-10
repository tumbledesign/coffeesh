colors = require './colors'
fs = require 'fs'
inspect = require('util').inspect

module.exports =
	'ttymgr': ->

		@PROMPT = "» "
		@TAB = "|··"
		@TAB_COLOR = 'grey7'
		@MINPROMPTHEIGHT = 6
		@CMD_TEXT = 'grey20'
		@CMD_BACKGROUND = 'grey5'
		@OUTPUT_TEXT = 'tempest'
		@OUTPUT_BACKGROUND = 'grey1'
		@INPUT_TEXT = 'grey20'
		@INPUT_BACKGROUND = 'grey2'
		@ERROR_TEXT = 'grey20'
		@ERROR_BACKGROUND = 'bloodRed'
		@STATUS_TEXT = 'grey1'
		@STATUS_BACKGROUND = 'dill'

		[@numcols, @numrows] = @output.getWindowSize()

		# buffer holds an array of lines of type [text, type]
		# for example, a buffer be [["a = 3","input"],["3","output"],["ls", "input"],[<output of ls>, "output"]]
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
		@redrawOutput()
		@redrawPrompt()


	redrawPrompt: ->
		@output.cursorTo 0, @promptRow - 1
		@output.write colors["bg"+ @STATUS_BACKGROUND] + colors[@STATUS_TEXT]
		@output.clearLine 0
		@output.cursorTo @numcols - (@cwd.length + 3)
		@output.write "(" + @cwd + ")"
		for r in [@promptRow...@numrows]
			@output.cursorTo 0, r
			@output.write colors["bg"+ @CMD_BACKGROUND] + colors[@CMD_TEXT]
			@output.clearLine 0
			if r is @promptRow
				line = "#{if @user is 'root' then colors.red else colors.green}#{@PROMPT + colors['bg'+ @CMD_BACKGROUND] + colors[@CMD_TEXT]}" 
			else
				@output.cursorTo @PROMPT.length, r
				line = ""
			if r - @promptRow < @cLines.length
				tab_adj = 0
				line += @cLines[r - @promptRow].replace /\t/g, (str, offset) =>
					tab_adj += @TAB.length - 1 if offset < @cx
					@TAB[@TAB_COLOR]
			@output.write line
		@output.cursorTo(@PROMPT.length + @cx + tab_adj, @promptRow + @cy)

		
	redrawOutput: ->
		for r in [0...@promptRow-1]
			@output.cursorTo 0, r
			if r + @scrollOffset >= @buffer.length
				@output.write colors["bg"+@OUTPUT_BACKGROUND] + colors[@OUTPUT_TEXT]
				@output.clearLine 0
			else
				type = @buffer[r + @scrollOffset][1]
				bgcol = @["#{type}_BACKGROUND"]
				fgcol = @["#{type}_TEXT"]
				@output.write colors["bg#{bgcol}"] + colors[fgcol]
				@output.clearLine 0
				line = @buffer[r + @scrollOffset][0]
				line = line.replace(/\u001b\[39m/g, colors[fgcol]).replace(/\u001b\[49m/g,colors[bgcol])
				line = line.replace(/\u001b\[0m/g, "\033[22m\033[23m\033[24m\033[27m#{colors["bg#{bgcol}"] + colors[fgcol]}")
				#@displayDebug line
				#line = line.truncStyle(@numcols)
				line = line[...line.length-1] + "…".white.bold if @buffer[r + @scrollOffset][0].removeStyle.length > @numcols
				line = "> #{line}".bold if type is 'INPUT'
				@output.write line
				#@displayDebug line

		@output.cursorTo(@PROMPT.length + @cx, @promptRow + @cy)

			
	scrollDown: (n) ->
		return if n? and n < 1

		# Can't scroll down if not enough lines have been output
		return if @buffer.length < @promptRow

		# Scroll to bottom
		if not n? or @buffer.length - (@scrollOffset + n) <= @promptRow - 1
			@scrollOffset = Math.max(0, @buffer.length - (@promptRow - 1))

		# Scroll n lines
		else
			@scrollOffset += n

		@redrawOutput()

	scrollUp: (n) ->
		return if n? and n < 1

		# Can't scroll up if not enough lines have been output
		return if @buffer.length < @promptRow - 1

		#Scroll to top
		if not n? or @scrollOffset - n <= 0
			@scrollOffset = 0

		else
			@scrollOffset -= n

		@redrawOutput()

	displayDebug: (debug) ->
		if typeof debug isnt 'string'
			debug = inspect(debug, true, null, true)
		fs.write  @debuglog, debug+"\n\n---------------------------------------\n\n"

	displayError: (err) ->
		if typeof err isnt 'string'
			err = inspect(err, true, 2, true)

		@displayBuffer err, 'ERROR'

		@redrawPrompt()
		fs.write @errlog, err+"\n\n---------------------------------------\n\n"

	displayOutput: (data) ->
		if typeof data isnt 'string'
			data = inspect(data, true, 3, true)
		@output.cursorTo 0, @row

		@displayBuffer data, 'OUTPUT'
		
		@output.cursorTo(@PROMPT.length + @cx, @promptRow + @cy)
		fs.write @outlog, data+"\n\n---------------------------------------\n\n"

	displayInput: (data) ->
		
		@output.cursorTo 0, @row
		@redrawPrompt()
		@displayBuffer data, 'INPUT'

		fs.write @inlog, data+"\n\n---------------------------------------\n\n"

	displayBuffer: (str, type = 'OUTPUT') ->
		numbuffered = 0
		lines = str.split(/\r\n|\n|\r/)
		realchar = ///
			(?:  \u001b\[(?: \d+;?)+m )+ [\s\S]
			| [\s\S]
		///g

		newlines = []
		for line in lines
		 	matches = line.match(realchar)
		 	if matches.length > @numcols
		 	else
				while matches.length > 0
					newlines.push matches[...@numcols].join('')
					matches = matches[@numcols...]
		
		for nl in newlines
			@buffer.push [nl, type]
			numbuffered++
		
		@row += numbuffered
		if @row > @promptRow - 1
			@scrollDown()
		else
			@redrawOutput()

		
		