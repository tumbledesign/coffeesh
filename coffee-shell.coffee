# Coffeescript Shell
#
#
#

# Start by opening up `stdin` and `stdout`.
stdin = process.openStdin()
stdout = process.stdout

# Require the **coffee-script** module to get access to the compiler.
CoffeeScript = require 'coffee-script'
readline     = require 'readline'
{inspect}    = require 'util'
{Script}     = require 'vm'
Module       = require 'module'
fs           = require 'fs'
spawn        = require('child_process').spawn
blockingProc = no


# Load built-in shell commands
global.pwd   = process.cwd
global.echo  = (val, showhidden = no, depth = 3, colors = yes) ->
  console.log inspect val, showhidden, depth, colors
global.kill  = (pid, signal = "SIGTERM") -> process.kill pid, signal
global.which = ->
global.cd    = (dir) -> process.chdir(dir)

# Load all executables from PATH
for path in process.env.PATH.split ':'
  do (path) ->
    for file in fs.readdirSync path
      do (file) ->
        global[file] ?= (args...) ->
          blockingProc = yes
          proc = spawn path + "/" + file, args, {
            cwd: process.cwd()
            env: process.env
            setsid: false
          }
          proc.stdout.on 'data', (data) -> process.stdout.write(data)
          proc.stderr.on 'data', (data) -> process.stderr.write(data)
          proc.on 'exit', ->
            blockingProc = no
            repl.setPrompt REPL_PROMPT()
            repl.prompt()

# Export environment vars to the global namespace
for key,val of process.env
  if global[key]? then global["$"+key] = val else global[key] = val


# REPL Setup

# Config
REPL_PROMPT = -> "#{process.cwd()}$ "
REPL_PROMPT_MULTILINE = '------> '
REPL_PROMPT_CONTINUATION = '......> '
REPL_HISTORY_FILE = process.env.HOME + '/.coffee_history'

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
  text = text.substr 0, repl.cursor
  text = text.split(' ').pop()
  completeFile(text) or completeAttribute(text) or completeVariable(text) or [[], text]

# Attempt to autocomplete a valid file or directory
completeFile = (text) ->
  dirs = text.split '/'
  if text[0] is '/' then dirs[0] = '/'
  prefix = dirs.pop()
  if dirs.length > 0 then listing = fs.readdirSync dirs.join "/"
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

# Create the REPL by listening to **stdin**.
if readline.createInterface.length < 3
  repl = readline.createInterface stdin, autocomplete
  stdin.on 'data', (buffer) -> repl.write buffer
else
  repl = readline.createInterface stdin, stdout, autocomplete


# load history
repl.history = fs.readFileSync(REPL_HISTORY_FILE, 'utf-8').split('\n').reverse()
repl.history.shift()
repl.historyIndex = -1
history_fd = fs.openSync REPL_HISTORY_FILE, 'a'

# Make sure that uncaught exceptions don't kill the REPL.
process.on 'uncaughtException', error

# The current backlog of multi-line code.
backlog = ''

multilineMode = off

repl.on 'SIGINT', ->
  backlog = ''
  multilineMode = off
  repl.historyIndex = -1
  repl.output.write '\n'
  repl.line = ''
  repl.setPrompt REPL_PROMPT()
  repl.prompt()

repl.on 'close', ->
  fs.closeSync history_fd
  repl.output.write '\n'
  repl.input.destroy()

# The main REPL function. **run** is called every time a line of code is entered.
# Attempt to evaluate the command. If there's an exception, print it out instead
# of exiting.
repl.on 'line', (buffer) ->
  if multilineMode
    backlog += "#{buffer}\n"
    repl.setPrompt REPL_PROMPT_CONTINUATION
    repl.prompt()
    return
  if !buffer.toString().trim() and !backlog
    repl.prompt()
    return
  code = backlog += buffer
  if code[code.length - 1] is '\\'
    backlog = "#{backlog[...-1]}\n"
    repl.setPrompt REPL_PROMPT_CONTINUATION
    repl.prompt()
    return
  backlog = ''
  try
    _ = global._
    returnValue = CoffeeScript.eval "_=(#{code}\n)", {
      filename: 'repl'
      modulename: 'repl'
    }
    if returnValue is undefined
      global._ = _
    if returnValue? then echo returnValue
    fs.write history_fd, code + '\n'
  catch err
    error err
  if not blockingProc
    repl.setPrompt REPL_PROMPT()
    repl.prompt()

exports.run = ->
  repl.setPrompt REPL_PROMPT()
  repl.prompt()
