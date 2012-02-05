styles = 
	'bold'        : (s) -> "\033[1m#{s}\033[22m"
	'faint'       : (s) -> "\033[2m#{s}\033[22m"
	'italic'      : (s) -> "\033[3m#{s}\033[23m"
	'underline'   : (s) -> "\033[4m#{s}\033[24m"
	'inverse'     : (s) -> "\033[7m#{s}\033[27m"
	'removeStyle' : (s) -> s.replace(/\u001b\[\d+m/g,'')

for color, offset of {black: 0, red: 1, green: 2, yellow: 3, blue: 4, magenta: 5, cyan: 6, white: 7, grey: 60}
	do (offset)->
		styles[color] = (s) -> "\033[#{offset+30}m#{s}\033[39m"
		styles["bg#{color}"] = (s) -> "\033[#{offset+40}m#{s}\033[49m"
for prop, func of styles
	do (prop, func) =>
		module.exports[prop] = (str) -> func(str)
		String::__defineGetter__ prop, -> func(@)