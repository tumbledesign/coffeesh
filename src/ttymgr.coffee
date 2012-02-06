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
		
		
		#@MOUSETRACK = "\x1b[?1003h\x1b[?1005h"
		#@MOUSEUNTRACK = "\x1b[?1003l\x1b[?1005l"
		
		
		[@numcols, @numrows] = @output.getWindowSize()
		@numrows-- unless @STATUSBAR is off

		process.on "SIGWINCH", => 
			[@numcols, @numrows] = @output.getWindowSize()
			@numrows-- unless @STATUSBAR is off
		@buffer = []
		for r in [0...@numrows]
			line = ""
			for c in [0...@numcols]
				line += " "
			@buffer.push line

		@promptRow = => (@numrows - Math.max(@MINPROMPTHEIGHT, @cLines.length)) 
		@topRow = 0
		@scrollOffset = 0
		[@col, @row] = [0, 0]

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


	reDraw: ->
		@output.cursorTo 0, 0
		@output.write colors.reset
		for r in [0..@promptRow()]
			@output.cursorTo 0, r
			row_in_buffer = @topRow - @scrollOffset + r
			if @buffer.length <= row_in_buffer
				@output.clearLine(0)
			else
				@output.write @buffer[row_in_buffer]
			

		@redrawStatus() unless @STATUSBAR is off
		@redrawPrompt()
		

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
		@output.cursorTo((p.removeStyle).length + @cx, @promptRow() + @cy)
				
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

	displayDebug: (debug) ->
		fs.write  @debuglog, debug

	displayError: (err) ->
		@output.cursorTo 0, @row
		@output.write colors["bg"+@OUTPUT_BACKGROUND] or colors.bgdefault
		@output.write colors.red
		@displayBuffer data

		@redrawPrompt()
		fs.write  @errlog, err

	displayOutput: (data) ->
		@output.cursorTo 0, @row
		@output.write colors["bg"+@OUTPUT_BACKGROUND] or colors.bgdefault

		@displayBuffer data

		@output.cursorTo((@PROMPT().removeStyle).length + @cx, @promptRow() + @cy)
		fs.write  @outlog, data

	displayInput: (data) ->
		@output.cursorTo 0, @row
		@output.write colors["bg"+@OUTPUT_BACKGROUND] or colors.bgdefault
		@output.write colors.bold

		@displayBuffer data

		@redrawPrompt()

		fs.write  @inlog, data

	displayBuffer: (str) ->
		lines = str.split(/\r\n|\n|\r/)
		for line in lines
			while line.length > 0
				@buffer.push = line[...@numrows]
				line = line[@numrows...]
				if @row is @promptRow() - 1
					@scrollDown()
				else @row++
				@output.write "#{line}\r\n"