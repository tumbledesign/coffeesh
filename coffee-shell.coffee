# Coffeescript Shell
#
#
#

# Start by opening up `stdin` and `stdout`.
stdin = process.openStdin()
stdout = process.stdout

# Require the **coffee-script** module to get access to the compiler.
global.CoffeeScript = require 'coffee-script'
readline     = require 'readline'
{inspect}    = require 'util'
{Script}     = require 'vm'
Module       = require 'module'
fs           = require 'fs'
path         = require 'path'
spawn        = require('child_process').spawn
blockingProc = no


# Load built-in shell commands
global.pwd   = process.cwd
global.echo  = (val, showhidden = no, depth = 3, colors = yes) ->
  console.log inspect val, showhidden, depth, colors
global.kill  = (pid, signal = "SIGTERM") -> process.kill pid, signal
global.which = ->
global.cd    = (dir) -> process.chdir(dir)
global.binaries = []

# Load all executables from PATH
for pathname in process.env.PATH.split ':'
  if path.existsSync pathname then do (pathname) ->
    for file in fs.readdirSync pathname
      do (file) ->
        global.binaries[file] ?= (args...) ->
          #args = (arg for arg in args when arg isnt 'BLANKEND')
          blockingProc = yes
          proc = spawn pathname + "/" + file, args, {
            cwd: process.cwd()
            env: process.env
            setsid: false
          }
          proc.stdout.on 'data', (data) -> process.stdout.write(data)
          proc.stderr.on 'data', (data) -> process.stderr.write(data)
          proc.on 'exit', ->
            blockingProc = no
            shell.setPrompt SHELL_PROMPT()
            shell.prompt()

# Export environment vars to the global namespace
for key,val of process.env
  if global[key]? then global["$"+key] = val else global[key] = val


# Config
SHELL_PROMPT = -> "#{process.cwd()}$ "
SHELL_PROMPT_CONTINUATION = '......> '
SHELL_HISTORY_FILE = process.env.HOME + '/.coffee_history'

enableColours = no
unless process.platform is 'win32'
  enableColours = not process.env.NODE_DISABLE_COLORS

# Log an error.
error = (err) ->
  stdout.write (err.stack or err.toString()) + '\n'

## Autocompletion

# Regexes to match complete-able bits of text.
ACCESSOR  = /\s*([\w\.]+)(?:\.(\w*))$/
SIMPLEVAR = /(\w+)$/i

# Returns a list of completions, and the completed text.
autocomplete = (text) ->
  text = text.substr 0, shell.cursor
  text = text.split(' ').pop()
  completeFile(text) or completeAttribute(text) or completeVariable(text) or [[], text]

# Attempt to autocomplete a valid file or directory
completeFile = (text) ->
  isdir = text is "" or text[text.length-1] is '/'
  dir = path.resolve text, (if isdir then '.' else '..')
  prefix = if isdir then '' else path.basename text
  if path.existsSync dir then listing = fs.readdirSync dir
  else listing = fs.readdirSync '.'
  completions = (el for el in listing when el.indexOf(prefix) is 0)
  if completions.length > 0
      [completions, prefix]

# Attempt to autocomplete a chained dotted attribute: `one.two.three`.
completeAttribute = (text) ->
  if match = text.match ACCESSOR
    [all, obj, prefix] = match
    try
      val = Script.runInThisContext obj
    catch error
      return
    completions = getCompletions prefix, Object.getOwnPropertyNames Object val
    [completions, prefix]

# Attempt to autocomplete an in-scope free variable: `one`.
completeVariable = (text) ->
  free = text.match(SIMPLEVAR)?[1]
  free = "" if text is ""
  if free?
    vars = Script.runInThisContext 'Object.getOwnPropertyNames(Object(this))'
    keywords = (r for r in CoffeeScript.RESERVED when r[..1] isnt '__')
    possibilities = vars.concat keywords
    completions = getCompletions free, possibilities
    [completions, free]

# Return elements of candidates for which `prefix` is a prefix.
getCompletions = (prefix, candidates) ->
  (el for el in candidates when el.indexOf(prefix) is 0)

# Create the shell by listening to **stdin**.
if readline.createInterface.length < 3
  shell = readline.createInterface stdin, autocomplete
  stdin.on 'data', (buffer) -> shell.write buffer
else
  shell = readline.createInterface stdin, stdout, autocomplete


# load history
shell.history = fs.readFileSync(SHELL_HISTORY_FILE, 'utf-8').split('\n').reverse()
shell.history.shift()
shell.historyIndex = -1
history_fd = fs.openSync SHELL_HISTORY_FILE, 'a'

# Make sure that uncaught exceptions don't kill the shell.
process.on 'uncaughtException', error

# The current backlog of multi-line code.
backlog = ''

multilineMode = off

shell.on 'SIGINT', ->
  backlog = ''
  multilineMode = off
  shell.historyIndex = -1
  shell.output.write '\n'
  shell.line = ''
  shell.setPrompt SHELL_PROMPT()
  shell.prompt()

shell.on 'close', ->
  fs.closeSync history_fd
  shell.output.write '\n'
  shell.input.destroy()

# The main SHELL function. **run** is called every time a line of code is entered.
# Attempt to evaluate the command. If there's an exception, print it out instead
# of exiting.
shell.on 'line', (buffer) ->
  if !buffer.toString().trim() and !backlog
    shell.prompt()
    return
  code = backlog += buffer
  if code[code.length - 1] is '\\'
    backlog = "#{backlog[...-1]}\n"
    shell.setPrompt SHELL_PROMPT_CONTINUATION
    shell.prompt()
    return
  backlog = ''
  output = [] ; args = [] ; cmd = ''
  pieces = code.split ' '
  while piece = pieces.shift()
    if piece in CoffeeScript.RESERVED
      if cmd isnt ''
        eval_line = "binaries." + cmd + " " + args.join ', '
        eval_output = "CoffeeScript.eval \"#{eval_line}\", {filename: '#{__filename}', modulename: 'shell'}"
        output.push eval_output
        cmd = '' ; args = []
      output.push piece
      continue
    if cmd is ''
      if global.binaries[piece]?
        cmd = "#{piece}"
      else
        output.push piece
      continue
    else if "#{piece}"[0] is '-' or path.existsSync "#{piece}"
        args.push "'#{piece}'" 
    else args.push piece
    
  if cmd isnt ''
    eval_line = "binaries." + cmd + " " + args.join ', '
    eval_output = "CoffeeScript.eval \"#{eval_line}\", {filename: '#{__filename}', modulename: 'shell'}"
    output.push eval_output
  echo code
  code = output.join ' '
  try
    _ = global._
    returnValue = CoffeeScript.eval "_=(#{code}\n)", {
      filename: __filename
      modulename: 'shell'
    }
    if typeof returnValue is 'function' then returnValue()
    global._ = _ if returnValue is undefined
    #if returnValue? then echo returnValue
    fs.write history_fd, code + '\n'
  catch err
    error err
  if not blockingProc
    shell.setPrompt SHELL_PROMPT()
    shell.prompt()

exports.run = ->
  shell.setPrompt SHELL_PROMPT()
  shell.prompt()
