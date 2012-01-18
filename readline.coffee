Interface = (input, output, completer) ->
  return new Interface(input, output, completer)  unless this instanceof Interface
  EventEmitter.call this
  completer = completer or ->
    []

  throw new TypeError("Argument 'completer' must be a function")  if typeof completer isnt "function"
  self = this
  @output = output
  @input = input
  input.resume()
  @completer = (if completer.length is 2 then completer else (v, callback) ->
    callback null, completer(v)
  )
  @setPrompt "> "
  @enabled = output.isTTY
  @enabled = false  if parseInt(process.env["NODE_NO_READLINE"], 10)
  unless @enabled
    input.on "data", (data) ->
      self._normalWrite data
  else
    input.on "keypress", (s, key) ->
      self._ttyWrite s, key

    @line = ""
    tty.setRawMode true
    @enabled = true
    @cursor = 0
    @history = []
    @historyIndex = -1
    winSize = output.getWindowSize()
    exports.columns = winSize[0]
    if process.listeners("SIGWINCH").length is 0
      process.on "SIGWINCH", ->
        winSize = output.getWindowSize()
        exports.columns = winSize[0]
commonPrefix = (strings) ->
  return ""  if not strings or strings.length is 0
  sorted = strings.slice().sort()
  min = sorted[0]
  max = sorted[sorted.length - 1]
  i = 0
  len = min.length

  while i < len
    return min.slice(0, i)  unless min[i] is max[i]
    i++
  min
kHistorySize = 30
kBufSize = 10 * 1024
util = require("util")
inherits = require("util").inherits
EventEmitter = require("events").EventEmitter
tty = require("tty")
exports.createInterface = (input, output, completer) ->
  new Interface(input, output, completer)

inherits Interface, EventEmitter
Interface::__defineGetter__ "columns", ->
  exports.columns

Interface::setPrompt = (prompt, length) ->
  @_prompt = prompt
  if length
    @_promptLength = length
  else
    lines = prompt.split(/[\r\n]/)
    lastLine = lines[lines.length - 1]
    @_promptLength = Buffer.byteLength(lastLine)

Interface::prompt = (preserveCursor) ->
  if @enabled
    @cursor = 0  unless preserveCursor
    @_refreshLine()
  else
    @output.write @_prompt

Interface::question = (query, cb) ->
  if cb
    @resume()
    if @_questionCallback
      @output.write "\n"
      @prompt()
    else
      @_oldPrompt = @_prompt
      @setPrompt query
      @_questionCallback = cb
      @output.write "\n"
      @prompt()

Interface::_onLine = (line) ->
  if @_questionCallback
    cb = @_questionCallback
    @_questionCallback = null
    @setPrompt @_oldPrompt
    cb line
  else
    @emit "line", line

Interface::_addHistory = ->
  return ""  if @line.length is 0
  @history.unshift @line
  @line = ""
  @historyIndex = -1
  @cursor = 0
  @history.pop()  if @history.length > kHistorySize
  @history[0]

Interface::_refreshLine = ->
  return  if @_closed
  @output.cursorTo 0
  @output.write @_prompt
  @output.write @line
  @output.clearLine 1
  @output.cursorTo @_promptLength + @cursor

Interface::close = (d) ->
  return  if @_closing
  @_closing = true
  tty.setRawMode false  if @enabled
  @emit "close"
  @_closed = true

Interface::pause = ->
  tty.setRawMode false  if @enabled

Interface::resume = ->
  tty.setRawMode true  if @enabled

Interface::write = (d, key) ->
  return  if @_closed
  (if @enabled then @_ttyWrite(d, key) else @_normalWrite(d, key))

Interface::_normalWrite = (b) ->
  @_onLine b.toString()  if b isnt `undefined`

Interface::_insertString = (c) ->
  if @cursor < @line.length
    beg = @line.slice(0, @cursor)
    end = @line.slice(@cursor, @line.length)
    @line = beg + c + end
    @cursor += c.length
    @_refreshLine()
  else
    @line += c
    @cursor += c.length
    @output.write c

Interface::_tabComplete = ->
  self = this
  self.pause()
  self.completer self.line.slice(0, self.cursor), (err, rv) ->
    self.resume()
    return  if err
    completions = rv[0]
    completeOn = rv[1]
    if completions and completions.length
      if completions.length is 1
        self._insertString completions[0].slice(completeOn.length)
      else
        handleGroup = (group) ->
          return  if group.length is 0
          minRows = Math.ceil(group.length / maxColumns)
          row = 0

          while row < minRows
            col = 0

            while col < maxColumns
              idx = row * maxColumns + col
              break  if idx >= group.length
              item = group[idx]
              self.output.write item
              if col < maxColumns - 1
                s = 0
                itemLen = item.length

                while s < width - itemLen
                  self.output.write " "
                  s++
              col++
            self.output.write "\r\n"
            row++
          self.output.write "\r\n"
        self.output.write "\r\n"
        width = completions.reduce((a, b) ->
          (if a.length > b.length then a else b)
        ).length + 2
        maxColumns = Math.floor(self.columns / width) or 1
        group = []
        c = undefined
        i = 0
        compLen = completions.length

        while i < compLen
          c = completions[i]
          if c is ""
            handleGroup group
            group = []
          else
            group.push c
          i++
        handleGroup group
        f = completions.filter((e) ->
          e  if e
        )
        prefix = commonPrefix(f)
        self._insertString prefix.slice(completeOn.length)  if prefix.length > completeOn.length
      self._refreshLine()

Interface::_wordLeft = ->
  if @cursor > 0
    leading = @line.slice(0, @cursor)
    match = leading.match(/([^\w\s]+|\w+|)\s*$/)
    @cursor -= match[0].length
    @_refreshLine()

Interface::_wordRight = ->
  if @cursor < @line.length
    trailing = @line.slice(@cursor)
    match = trailing.match(/^(\s+|\W+|\w+)\s*/)
    @cursor += match[0].length
    @_refreshLine()

Interface::_deleteLeft = ->
  if @cursor > 0 and @line.length > 0
    @line = @line.slice(0, @cursor - 1) + @line.slice(@cursor, @line.length)
    @cursor--
    @_refreshLine()

Interface::_deleteRight = ->
  @line = @line.slice(0, @cursor) + @line.slice(@cursor + 1, @line.length)
  @_refreshLine()

Interface::_deleteWordLeft = ->
  if @cursor > 0
    leading = @line.slice(0, @cursor)
    match = leading.match(/([^\w\s]+|\w+|)\s*$/)
    leading = leading.slice(0, leading.length - match[0].length)
    @line = leading + @line.slice(@cursor, @line.length)
    @cursor = leading.length
    @_refreshLine()

Interface::_deleteWordRight = ->
  if @cursor < @line.length
    trailing = @line.slice(@cursor)
    match = trailing.match(/^(\s+|\W+|\w+)\s*/)
    @line = @line.slice(0, @cursor) + trailing.slice(match[0].length)
    @_refreshLine()

Interface::_deleteLineLeft = ->
  @line = @line.slice(@cursor)
  @cursor = 0
  @_refreshLine()

Interface::_deleteLineRight = ->
  @line = @line.slice(0, @cursor)
  @_refreshLine()

Interface::_line = ->
  line = @_addHistory()
  @output.write "\r\n"
  @_onLine line

Interface::_historyNext = ->
  if @historyIndex > 0
    @historyIndex--
    @line = @history[@historyIndex]
    @cursor = @line.length
    @_refreshLine()
  else if @historyIndex is 0
    @historyIndex = -1
    @cursor = 0
    @line = ""
    @_refreshLine()

Interface::_historyPrev = ->
  if @historyIndex + 1 < @history.length
    @historyIndex++
    @line = @history[@historyIndex]
    @cursor = @line.length
    @_refreshLine()

Interface::_attemptClose = ->
  if @listeners("attemptClose").length
    @emit "attemptClose"
  else
    @close()

Interface::_ttyWrite = (s, key) ->
  next_word = undefined
  next_non_word = undefined
  previous_word = undefined
  previous_non_word = undefined
  key = key or {}
  if key.ctrl and key.shift
    switch key.name
      when "backspace"
        @_deleteLineLeft()
      when "delete"
        @_deleteLineRight()
  else if key.ctrl
    switch key.name
      when "c"
        if @listeners("SIGINT").length
          @emit "SIGINT"
        else
          @_attemptClose()
      when "h"
        @_deleteLeft()
      when "d"
        if @cursor is 0 and @line.length is 0
          @_attemptClose()
        else @_deleteRight()  if @cursor < @line.length
      when "u"
        @cursor = 0
        @line = ""
        @_refreshLine()
      when "k"
        @_deleteLineRight()
      when "a"
        @cursor = 0
        @_refreshLine()
      when "e"
        @cursor = @line.length
        @_refreshLine()
      when "b"
        if @cursor > 0
          @cursor--
          @_refreshLine()
      when "f"
        unless @cursor is @line.length
          @cursor++
          @_refreshLine()
      when "n"
        @_historyNext()
      when "p"
        @_historyPrev()
      when "z"
        process.kill process.pid, "SIGTSTP"
        return
      when "w", "backspace"
        @_deleteWordLeft()
      when "delete"
        @_deleteWordRight()
      when "backspace"
        @_deleteWordLeft()
      when "left"
        @_wordLeft()
      when "right"
        @_wordRight()
  else if key.meta
    switch key.name
      when "b"
        @_wordLeft()
      when "f"
        @_wordRight()
      when "d", "delete"
        @_deleteWordRight()
      when "backspace"
        @_deleteWordLeft()
  else
    switch key.name
      when "enter"
        @_line()
      when "backspace"
        @_deleteLeft()
      when "delete"
        @_deleteRight()
      when "tab"
        @_tabComplete()
      when "left"
        if @cursor > 0
          @cursor--
          @output.moveCursor -1, 0
      when "right"
        unless @cursor is @line.length
          @cursor++
          @output.moveCursor 1, 0
      when "home"
        @cursor = 0
        @_refreshLine()
      when "end"
        @cursor = @line.length
        @_refreshLine()
      when "up"
        @_historyPrev()
      when "down"
        @_historyNext()
      else
        s = s.toString("utf-8")  if Buffer.isBuffer(s)
        if s
          lines = s.split(/\r\n|\n|\r/)
          i = 0
          len = lines.length

          while i < len
            @_line()  if i > 0
            @_insertString lines[i]
            i++

exports.Interface = Interface