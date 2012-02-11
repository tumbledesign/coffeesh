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
		
		process.env.LS_COLORS="rs=48;5;233;38;5;103;22;23;24;27:di=01;34:ln=01;36:mh=00:pi=40;33:so=01;35:do=01;35:bd=40;33;01:cd=40;33;01:or=40;31;01:su=37;41:sg=30;43:ca=30;41:tw=30;42:ow=34;42:st=37;44:ex=01;32:*.tar=01;31:*.tgz=01;31:*.arj=01;31:*.taz=01;31:*.lzh=01;31:*.lzma=01;31:*.tlz=01;31:*.txz=01;31:*.zip=01;31:*.z=01;31:*.Z=01;31:*.dz=01;31:*.gz=01;31:*.lz=01;31:*.xz=01;31:*.bz2=01;31:*.bz=01;31:*.tbz=01;31:*.tbz2=01;31:*.tz=01;31:*.deb=01;31:*.rpm=01;31:*.jar=01;31:*.rar=01;31:*.ace=01;31:*.zoo=01;31:*.cpio=01;31:*.7z=01;31:*.rz=01;31:*.jpg=01;35:*.jpeg=01;35:*.gif=01;35:*.bmp=01;35:*.pbm=01;35:*.pgm=01;35:*.ppm=01;35:*.tga=01;35:*.xbm=01;35:*.xpm=01;35:*.tif=01;35:*.tiff=01;35:*.png=01;35:*.svg=01;35:*.svgz=01;35:*.mng=01;35:*.pcx=01;35:*.mov=01;35:*.mpg=01;35:*.mpeg=01;35:*.m2v=01;35:*.mkv=01;35:*.ogm=01;35:*.mp4=01;35:*.m4v=01;35:*.mp4v=01;35:*.vob=01;35:*.qt=01;35:*.nuv=01;35:*.wmv=01;35:*.asf=01;35:*.rm=01;35:*.rmvb=01;35:*.flc=01;35:*.avi=01;35:*.fli=01;35:*.flv=01;35:*.gl=01;35:*.dl=01;35:*.xcf=01;35:*.xwd=01;35:*.yuv=01;35:*.cgm=01;35:*.emf=01;35:*.axv=01;35:*.anx=01;35:*.ogv=01;35:*.ogx=01;35:*.aac=00;36:*.au=00;36:*.flac=00;36:*.mid=00;36:*.midi=00;36:*.mka=00;36:*.mp3=00;36:*.mpc=00;36:*.ogg=00;36:*.ra=00;36:*.wav=00;36:*.axa=00;36:*.oga=00;36:*.spx=00;36:*.xspf=00;36:"

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
			
		process.on

	mouseTracking: (e = on) ->
		if e then @output.write "\x1b[?1003h\x1b[?1005h"
		else @output.write "\x1b[?1003l\x1b[?1005l"
	
	clearPrompt: ->
		@output.write "\x1b[u\x1b[48;5;233m\x1b[38;5;103m\x1b[0J"
		
	spaceForPrompt: ->
		@output.write "\n" for i in [0...@MINPROMPTHEIGHT]
		@output.write "\x1b[#{@MINPROMPTHEIGHT}A\x1b[s"

	drawShell: ->
		#@redrawOutput()
		@output.write "\x1b[H\x1b[s"
		@clearPrompt()
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

		
#	redrawOutput: ->
#		return
#		for r in [0...@promptRow-1]
#			@output.cursorTo 0, r
#			if r + @scrollOffset >= @buffer.length
#			#	@output.write colors["bg"+@OUTPUT_BACKGROUND] + colors[@OUTPUT_TEXT]
#			#	@output.clearLine 0
#			else
#				type = @buffer[r + @scrollOffset][1]
#				bgcol = @["#{type}_BACKGROUND"]
#				fgcol = @["#{type}_TEXT"]
#				@output.write colors["bg#{bgcol}"] + colors[fgcol]
#				@output.clearLine 0
#				line = @buffer[r + @scrollOffset][0]
#				line = line.replace(/\u001b\[39m/g, colors[fgcol]).replace(/\u001b\[49m/g,colors[bgcol])
#				line = line.replace(/\u001b\[0m/g, "\033[22m\033[23m\033[24m\033[27m#{colors["bg#{bgcol}"] + colors[fgcol]}")
#				#@displayDebug line
#				#line = line.truncStyle(@numcols)
#				line = line[...line.length-1] + "…".white.bold if @buffer[r + @scrollOffset][0].removeStyle.length > @numcols
#				line = "> #{line}".bold if type is 'INPUT'
#				@output.write line
#				#@displayDebug line
#
#		@output.cursorTo(@PROMPT.length + @cx, @promptRow + @cy)

			
#	scrollDown: (n) ->
#		return if n? and n < 1
#
#		# Can't scroll down if not enough lines have been output
#		return if @buffer.length < @promptRow
#
#		# Scroll to bottom
#		if not n? or @buffer.length - (@scrollOffset + n) <= @promptRow - 1
#			@scrollOffset = Math.max(0, @buffer.length - (@promptRow - 1))
#
#		# Scroll n lines
#		else
#			@scrollOffset += n
#
#		@redrawOutput()
#
#	scrollUp: (n) ->
#		return if n? and n < 1
#
#		# Can't scroll up if not enough lines have been output
#		return if @buffer.length < @promptRow - 1
#
#		#Scroll to top
#		if not n? or @scrollOffset - n <= 0
#			@scrollOffset = 0
#
#		else
#			@scrollOffset -= n
#
#		@redrawOutput()

	displayDebug: (debug) ->
		if typeof debug isnt 'string'
			debug = inspect(debug, true, null, true)
		fs.write  @debuglog, debug+"\n\n---------------------------------------\n\n"

	displayError: (err) ->
		if typeof err isnt 'string'
			err = inspect(err, true, 2, true)

		@output.write '\x1b[u\x1b[38;5;252m\x1b[48;5;52m\x1b[0J'+err+'\n'
		#@displayBuffer err, 'ERROR'
		@spaceForPrompt()
		@redrawPrompt()
		fs.write @errlog, err+"\n\n---------------------------------------\n\n"

	displayOutput: (data) ->
		if typeof data isnt 'string'
			data = inspect(data, true, 3, true)
		#@output.cursorTo 0, @row
		@clearPrompt()
		bgcol = @["#OUTPUT_BACKGROUND"]
		fgcol = @["#OUTPUT_TEXT"]
		#@output.write colors["bg#{bgcol}"] + colors[fgcol]
		#@output.clearLine 0
		
		#data = data.replace(/\u001b\[39m/g, colors[fgcol]).replace(/\u001b\[49m/g,colors[bgcol])
		#data = data.replace(/\u001b\[0m/g, "\033[22m\033[23m\033[24m\033[27m#{colors["bg#{bgcol}"] + colors[fgcol]}")
		
		@output.write data + '\n'
		@spaceForPrompt()
		#@displayBuffer data, 'OUTPUT'
		#@output.cursorTo(@PROMPT.length + @cx, @promptRow + @cy)
		@redrawPrompt()
		fs.write @outlog, data+"\n\n---------------------------------------\n\n"

	displayInput: (data) ->
		
		#@output.cursorTo 0, @row
		#@clearPrompt()
		#@displayBuffer data, 'INPUT'
		@output.write '\x1b[u\x1b[38;5;252m\x1b[48;5;234m\x1b[0J'+data+'\n'
		@spaceForPrompt()
		@redrawPrompt()
		fs.write @inlog, data+"\n\n---------------------------------------\n\n"

#	displayBuffer: (str, type = 'OUTPUT') ->
#		numbuffered = 0
#		lines = str.split(/\r\n|\n|\r/)
#		realchar = ///
#		(?:  \u001b\[(?: \d+;?)+m )+ [\s\S]
#		| [\s\S]
#	///g
#
#		newlines = []
#		for line in lines
#		 	matches = line.match(realchar)
#		 	if matches?.length > @numcols
#		 	else
#				while matches?.length > 0
#					newlines.push matches[...@numcols].join('')
#					matches = matches[@numcols...]
#		
#		for nl in newlines
#			@buffer.push [nl, type]
#			numbuffered++
#		
#		@row += numbuffered
#		if @row > @promptRow - 1
#			@scrollDown()
#		else
#			@redrawOutput()

		
		