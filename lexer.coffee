{Rewriter} = require './rewriter'
{count, starts, compact, last} = require('coffee-script').helpers

JS_KEYWORDS = ['true', 'false', 'null', 'this', 'new', 'delete', 'typeof', 'in', 'instanceof', 'return', 'throw', 'break', 'continue', 'debugger', 'if', 'else', 'switch', 'for', 'while', 'do', 'try', 'catch', 'finally', 'class', 'extends', 'super']
COFFEE_KEYWORDS = ['undefined', 'then', 'unless', 'until', 'loop', 'of', 'by', 'when']
COFFEE_ALIAS_MAP = and:'&&', or:'||', is:'==', isnt:'!=', not:'!', yes:'true', no:'false', on:'true', off:'false'
COFFEE_ALIASES  = (key for key of COFFEE_ALIAS_MAP)
COFFEE_KEYWORDS = COFFEE_KEYWORDS.concat COFFEE_ALIASES
RESERVED = ['case', 'default', 'function', 'var', 'void', 'with', 'const', 'let', 'enum', 'export', 'import', 'native', '__hasProp', '__extends', '__slice', '__bind', '__indexOf']
JS_FORBIDDEN = JS_KEYWORDS.concat RESERVED
exports.RESERVED = RESERVED.concat(JS_KEYWORDS).concat(COFFEE_KEYWORDS)

exports.Lexer = class Lexer

	tokenize: (code, opts = {}) ->
		TRAILING_SPACES = /\s+$/
		WHITESPACE = /^[^\n\S]+/
		code     = "\n#{code}" if WHITESPACE.test code
		code     = code.replace(/\r/g, '').replace TRAILING_SPACES, ''
		@code    = code           # The remainder of the source code.
		@line    = opts.line or 0 # The current line.
		@indent  = 0              # The current indentation level.
		@indebt  = 0              # The over-indentation at the current level.
		@outdebt = 0              # The under-outdentation at the current level.
		@indents = []             # The stack of all current indentation levels.
		@tokens  = []             # Stream of parsed tokens in the form `['TYPE', value, line]`.
		i = 0
		while @chunk = code.slice i
			i += @pathToken()       or
				@identifierToken() or
				@commentToken()    or
				@whitespaceToken() or
				@lineToken()       or
				@heredocToken()    or
				@stringToken()     or
				@numberToken()     or		
				@literalToken()
		@closeIndentation()
		(new Rewriter).rewrite @tokens

	pathToken: ->
		FILEPATH = /// ^
			(?:
				(?:	[-A-Za-z0-9_.+=%:@~] | [\x7f-\uffff] | \\[^n\\] )* # letter, digit, _, -, ., +, =, %, :, @, ~, utf8, any escaped char except \\ or \n
				(?:[/])
				(?:	[-A-Za-z0-9_.+=%:@~] | [\x7f-\uffff] | \\[^n\\] )* # letter, digit, _, -, ., +, =, %, :, @, ~, utf8, any escaped char except \\ or \n
				#(?![^\n\S])
			)+
		///
		NOT_FILEPATH = ['NUMBER', 'REGEX', 'BOOL', '++', '--', '(']
		NOT_SPACED_FILEPATH = NOT_FILEPATH.concat ']', ')', '}', 'THIS', 'STRING', 'IDENTIFIER'
		#SHELL_CONTROL = ['&', '|', '<', '>', '<<', '>>', '*', '~', '!', '-', '--', '/', '%', '+', '.', '$', '`', '\'', '"' ]
		prev = last @tokens
		return 0 if prev and (prev[0] in (if prev.spaced then NOT_FILEPATH else NOT_SPACED_FILEPATH))
		if @chunk in ['.', '..']
			@token 'FILEPATH', @makeString new String(@chunk), '"', no
			return @chunk.length
		return 0 unless match = FILEPATH.exec @chunk
		[filepath] = match
		if prev and prev[0] in ['BINARIES', 'BUILTIN', 'FILEPATH', 'ARG', 'IDENTIFIER']
			@token 'ARG', @makeString filepath, '"', no
			return filepath.length
		@token 'FILEPATH', "shl.execute.bind(shl,#{@makeString filepath, '"', no})"
		(filepath.length)

	identifierToken: ->
		IDENTIFIER = /// ^
			( [$A-Za-z_\x7f-\uffff][$\w\x7f-\uffff]* )
			( [^\n\S]* : (?!:) )?  # Is this a property name?
		///
		RELATION = ['IN', 'OF', 'INSTANCEOF']
		LINE_BREAK = ['INDENT', 'OUTDENT', 'TERMINATOR']
		UNARY   = ['!', '~', 'NEW', 'TYPEOF', 'DELETE', 'DO']
		return 0 unless match = IDENTIFIER.exec @chunk
		[input, id, colon] = match

		if builtin.hasOwnProperty id
			cmd = "builtin.#{id}"
			@token 'BUILTIN', cmd
			return id.length
		if binaries.hasOwnProperty id			
			cmdstr = @makeString "#{binaries[id]}/#{id}", '"', yes
			cmd = "shl.execute.bind(shl,#{cmdstr})"
			@token 'BINARIES', cmd
			return id.length
		if (prev = last @tokens) and prev[0] in ['BINARIES', 'BUILTIN', 'FILEPATH', 'ARG']
			arg = @makeString id, '"', yes
			@token 'ARG', arg
			return id.length
		if (prev = last @tokens) and 
				prev[0] in ['-', '--'] and 
				@tokens[@tokens.length-2][0] in ['BINARIES', 'BUILTIN', 'FILEPATH', 'ARG']
			arg = @makeString prev[0]+id, '"', yes
			@tokens.pop()
			@token 'ARG', arg
			return id.length
			
		if id is 'own' and @tag() is 'FOR'
			@token 'OWN', id
			return id.length
		forcedIdentifier = colon or
			(prev = last @tokens) and (prev[0] in ['.', '?.', '::'] or
			not prev.spaced and prev[0] is '@')
		tag = 'IDENTIFIER'
		if not forcedIdentifier and (id in JS_KEYWORDS or id in COFFEE_KEYWORDS)
			tag = id.toUpperCase()
			if tag is 'WHEN' and @tag() in LINE_BREAK
				tag = 'LEADING_WHEN'
			else if tag is 'FOR'
				@seenFor = yes
			else if tag is 'UNLESS'
				tag = 'IF'
			else if tag in UNARY
				tag = 'UNARY'
			else if tag in RELATION
				if tag isnt 'INSTANCEOF' and @seenFor
					tag = 'FOR' + tag
					@seenFor = no
				else
					tag = 'RELATION'
					if @value() is '!'
						@tokens.pop()
						id = '!' + id
		if id in ['eval', 'arguments'].concat JS_FORBIDDEN
			if forcedIdentifier
				tag = 'IDENTIFIER'
				id  = new String id
				id.reserved = yes
			else if id in RESERVED
				@identifierError id
		unless forcedIdentifier
			id  = COFFEE_ALIAS_MAP[id] if id in COFFEE_ALIASES
			tag = switch id
				when '!'                                  then 'UNARY'
				when '==', '!='                           then 'COMPARE'
				when '&&', '||'                           then 'LOGIC'
				when 'true', 'false', 'null', 'undefined' then 'BOOL'
				when 'break', 'continue', 'debugger'      then 'STATEMENT'
				else  tag
		@token tag, id
		@token ':', ':' if colon
		input.length

	numberToken: ->
		NUMBER     = ///
			^ 0x[\da-f]+ |                              # hex
			^ 0b[01]+ |                              # binary
			^ \d*\.?\d+ (?:e[+-]?\d+)?  # decimal
		///i
		return 0 unless match = NUMBER.exec @chunk
		number = match[0]
		@token 'NUMBER', number
		number.length

	stringToken: ->
		SIMPLESTR  = /^'[^\\']*(?:\\.[^\\']*)*'/
		MULTILINER = /\n/g
		token = if (prev = last @tokens) and prev[0] in ['BINARIES', 'BUILTIN', 'FILEPATH', 'ARG'] then 'ARG'	else 'STRING'
		switch @chunk.charAt 0
			when "'"
				return 0 unless match = SIMPLESTR.exec @chunk
				@token token, (string = match[0]).replace MULTILINER, '\\\n'
			when '"'
				return 0 unless string = @balancedString @chunk, '"'
				if 0 < string.indexOf '#{', 1
					@interpolateString string.slice 1, -1
				else
					@token token, @escapeLines string
			else
				return 0
		@line += count string, '\n'
		string.length

	heredocToken: ->
		HEREDOC    = /// ^ ("""|''') ([\s\S]*?) (?:\n[^\n\S]*)? \1 ///
		return 0 unless match = HEREDOC.exec @chunk
		heredoc = match[0]
		quote = heredoc.charAt 0
		doc = @sanitizeHeredoc match[2], quote: quote, indent: null
		if quote is '"' and 0 <= doc.indexOf '#{'
			@interpolateString doc, heredoc: yes
		else
			@token 'STRING', @makeString doc, quote, yes
		@line += count heredoc, '\n'
		heredoc.length

	commentToken: ->
		COMMENT    = /^###([^#][\s\S]*?)(?:###[^\n\S]*|(?:###)?$)|^(?:\s*#(?!##[^#]).*)+/
		return 0 unless match = @chunk.match COMMENT
		[comment, here] = match
		if here
			@token 'HERECOMMENT', @sanitizeHeredoc here,
				herecomment: true, indent: Array(@indent + 1).join(' ')
			@token 'TERMINATOR', '\n'
		@line += count comment, '\n'
		comment.length
		
	regexToken: ->
		REGEX = /// ^
			/ (?! [\s=] )       # disallow leading whitespace or equals signs
			[^ [ / \n \\ ]*  # every other thing
			(?:
				(?: \\[\s\S]   # anything escaped
					| \[         # character class
							[^ \] \n \\ ]*
							(?: \\[\s\S] [^ \] \n \\ ]* )*
						]
				) [^ [ / \n \\ ]*
			)*
			/ [imgy]{0,4} (?!\w)
		///
		HEREGEX = /// ^ /{3} ([\s\S]+?) /{3} ([imgy]{0,4}) (?!\w) ///
		NOT_REGEX = ['NUMBER', 'REGEX', 'BOOL', '++', '--', ']']
		NOT_SPACED_REGEX = NOT_REGEX.concat ')', '}', 'THIS', 'IDENTIFIER', 'STRING'
		return 0 if @chunk.charAt(0) isnt '/'
		if match = HEREGEX.exec @chunk
			length = @heregexToken match
			@line += count match[0], '\n'
			return length

		prev = last @tokens
		return 0 if prev and (prev[0] in (if prev.spaced then NOT_REGEX else NOT_SPACED_REGEX))
		return 0 unless match = REGEX.exec @chunk
		[regex] = match
		@token 'REGEX', if regex is '//' then '/(?:)/' else regex
		regex.length

	heregexToken: (match) ->
		HEREGEX_OMIT = /\s+(?:#.*)?/g
		[heregex, body, flags] = match
		if 0 > body.indexOf '#{'
			re = body.replace(HEREGEX_OMIT, '').replace(/\//g, '\\/')
			@token 'REGEX', "/#{ re or '(?:)' }/#{flags}"
			return heregex.length
		@token 'IDENTIFIER', 'RegExp'
		@tokens.push ['CALL_START', '(']
		tokens = []
		for [tag, value] in @interpolateString(body, regex: yes)
			if tag is 'TOKENS'
				tokens.push value...
			else
				continue unless value = value.replace HEREGEX_OMIT, ''
				value = value.replace /\\/g, '\\\\'
				tokens.push ['STRING', @makeString(value, '"', yes)]
			tokens.push ['+', '+']
		tokens.pop()
		@tokens.push ['STRING', '""'], ['+', '+'] unless tokens[0]?[0] is 'STRING'
		@tokens.push tokens...
		@tokens.push [',', ','], ['STRING', '"' + flags + '"'] if flags
		@token ')', ')'
		heregex.length

	lineToken: ->
		MULTI_DENT = /^(?:\n[^\n\S]*)+/
		return 0 unless match = MULTI_DENT.exec @chunk
		indent = match[0]
		@line += count indent, '\n'
		prev = last @tokens, 1
		size = indent.length - 1 - indent.lastIndexOf '\n'
		noNewlines = @unfinished()
		if size - @indebt is @indent
			if noNewlines then @suppressNewlines() else @newlineToken()
			return indent.length
		if size > @indent
			if noNewlines
				@indebt = size - @indent
				@suppressNewlines()
				return indent.length
			diff = size - @indent + @outdebt
			@token 'INDENT', diff
			@indents.push diff
			@outdebt = @indebt = 0
		else
			@indebt = 0
			@outdentToken @indent - size, noNewlines
		@indent = size
		indent.length

	outdentToken: (moveOut, noNewlines, close) ->
		while moveOut > 0
			len = @indents.length - 1
			if @indents[len] is undefined
				moveOut = 0
			else if @indents[len] is @outdebt
				moveOut -= @outdebt
				@outdebt = 0
			else if @indents[len] < @outdebt
				@outdebt -= @indents[len]
				moveOut  -= @indents[len]
			else
				dent = @indents.pop() - @outdebt
				moveOut -= dent
				@outdebt = 0
				@token 'OUTDENT', dent
		@outdebt -= moveOut if dent
		@tokens.pop() while @value() is ';'
		@token 'TERMINATOR', '\n' unless @tag() is 'TERMINATOR' or noNewlines
		this

	whitespaceToken: ->
		WHITESPACE = /^[^\n\S]+/
		return 0 unless (match = WHITESPACE.exec @chunk) or (nline = @chunk.charAt(0) is '\n')
		prev = last @tokens
		prev[if match then 'spaced' else 'newLine'] = true if prev
		if match then match[0].length else 0

	newlineToken: ->
		@tokens.pop() while @value() is ';'
		@token 'TERMINATOR', '\n' unless @tag() is 'TERMINATOR'
		this

	suppressNewlines: ->
		@tokens.pop() if @value() is '\\'
		this

	literalToken: ->
		OPERATOR   = /// ^ (
			?: [-=]>             # function
			| [-+*/%<>&|^!?=]=  # compound assign / compare
			| >>>=?             # zero-fill right shift
			| ([-+:])\1         # doubles
			| ([&|<>])\2=?      # logic / shift
			| \?\.              # soak access
			| \.{2,3}           # range or splat
		) ///
		CODE       = /^[-=]>/
		COMPOUND_ASSIGN = [ '-=', '+=', '/=', '*=', '%=', '||=', '&&=', '?=', '<<=', '>>=', '>>>=', '&=', '^=', '|=' ]
		UNARY   = ['!', '~', 'NEW', 'TYPEOF', 'DELETE', 'DO']
		LOGIC   = ['&&', '||', '&', '|', '^']
		SHIFT   = ['<<', '>>', '>>>']
		COMPARE = ['==', '!=', '<', '>', '<=', '>=']
		MATH    = ['*', '/', '%']
		BOOL = ['TRUE', 'FALSE', 'NULL', 'UNDEFINED']
		CALLABLE  = ['IDENTIFIER', 'STRING', ')', ']', '}', '?', '::', '@', 'THIS', 'SUPER']
		INDEXABLE = CALLABLE.concat 'NUMBER', 'BOOL'
		if match = OPERATOR.exec @chunk
			[value] = match
			@tagParameters() if CODE.test value
		else
			value = @chunk.charAt 0
		tag  = value
		prev = last @tokens
		if value is '=' and prev
			@assignmentError() if not prev[1].reserved and prev[1] in JS_FORBIDDEN
			if prev[1] in ['||', '&&']
				prev[0] = 'COMPOUND_ASSIGN'
				prev[1] += '='
				return value.length
		if      value is ';'             then tag = 'TERMINATOR'
		else if value in MATH            then tag = 'MATH'
		else if value in COMPARE         then tag = 'COMPARE'
		else if value in COMPOUND_ASSIGN then tag = 'COMPOUND_ASSIGN'
		else if value in UNARY           then tag = 'UNARY'
		else if value in SHIFT           then tag = 'SHIFT'
		else if value in LOGIC or value is '?' and prev?.spaced then tag = 'LOGIC'
		else if prev and not prev.spaced
			if value is '(' and prev[0] in CALLABLE
				prev[0] = 'FUNC_EXIST' if prev[0] is '?'
				tag = 'CALL_START'
			else if value is '[' and prev[0] in INDEXABLE
				tag = 'INDEX_START'
				switch prev[0]
					when '?'  then prev[0] = 'INDEX_SOAK'
		@token tag, value
		value.length

	sanitizeHeredoc: (doc, options) ->
		HEREDOC_INDENT  = /\n+([^\n\S]*)/g
		HEREDOC_ILLEGAL = /\*\//
		{indent, herecomment} = options
		if herecomment
			if HEREDOC_ILLEGAL.test doc
				throw new Error "block comment cannot contain \"*/\", starting on line #{@line + 1}"
			return doc if doc.indexOf('\n') <= 0
		else
			while match = HEREDOC_INDENT.exec doc
				attempt = match[1]
				indent = attempt if indent is null or 0 < attempt.length < indent.length
		doc = doc.replace /// \n #{indent} ///g, '\n' if indent
		doc = doc.replace /^\n/, '' unless herecomment
		doc

	tagParameters: ->
		return this if @tag() isnt ')'
		stack = []
		{tokens} = this
		i = tokens.length
		tokens[--i][0] = 'PARAM_END'
		while tok = tokens[--i]
			switch tok[0]
				when ')'
					stack.push tok
				when '(', 'CALL_START'
					if stack.length then stack.pop()
					else if tok[0] is '('
						tok[0] = 'PARAM_START'
						return this
					else return this
		this

	closeIndentation: ->
		@outdentToken @indent

	identifierError: (word) ->
		throw SyntaxError "Reserved word \"#{word}\" on line #{@line + 1}"

	assignmentError: ->
		throw SyntaxError "Reserved word \"#{@value()}\" on line #{@line + 1} can't be assigned"

	balancedString: (str, end) ->
		REGEX = /// ^
			/ (?! [\s=] )       # disallow leading whitespace or equals signs
			[^ [ / \n \\ ]*  # every other thing
			(?:
				(?: \\[\s\S]   # anything escaped
					| \[         # character class
							[^ \] \n \\ ]*
							(?: \\[\s\S] [^ \] \n \\ ]* )*
						]
				) [^ [ / \n \\ ]*
			)*
			/ [imgy]{0,4} (?!\w)
		///
		HEREGEX = /// ^ /{3} ([\s\S]+?) /{3} ([imgy]{0,4}) (?!\w) ///
		stack = [end]
		for i in [1...str.length]
			switch letter = str.charAt i
				when '\\'
					i++
					continue
				when end
					stack.pop()
					unless stack.length
						return str.slice 0, i + 1
					end = stack[stack.length - 1]
					continue
			if end is '}' and letter in ['"', "'"]
				stack.push end = letter
			else if end is '}' and letter is '/' and match = (HEREGEX.exec(str.slice i) or REGEX.exec(str.slice i))
				i += match[0].length - 1
			else if end is '}' and letter is '{'
				stack.push end = '}'
			else if end is '"' and prev is '#' and letter is '{'
				stack.push end = '}'
			prev = letter
		throw new Error "missing #{ stack.pop() }, starting on line #{ @line + 1 }"

	interpolateString: (str, options = {}) ->
		{heredoc, regex} = options
		tokens = []
		pi = 0
		i  = -1
		while letter = str.charAt i += 1
			if letter is '\\'
				i += 1
				continue
			unless letter is '#' and str.charAt(i+1) is '{' and
						 (expr = @balancedString str.slice(i + 1), '}')
				continue
			tokens.push ['NEOSTRING', str.slice(pi, i)] if pi < i
			inner = expr.slice(1, -1)
			if inner.length
				nested = new Lexer().tokenize inner, line: @line, rewrite: off
				nested.pop()
				nested.shift() if nested[0]?[0] is 'TERMINATOR'
				if len = nested.length
					if len > 1
						nested.unshift ['(', '(']
						nested.push    [')', ')']
					tokens.push ['TOKENS', nested]
			i += expr.length
			pi = i + 1
		tokens.push ['NEOSTRING', str.slice pi] if i > pi < str.length
		return tokens if regex
		return @token 'STRING', '""' unless tokens.length
		tokens.unshift ['', ''] unless tokens[0][0] is 'NEOSTRING'
		@token '(', '(' if interpolated = tokens.length > 1
		for [tag, value], i in tokens
			@token '+', '+' if i
			if tag is 'TOKENS'
				@tokens.push value...
			else
				@token 'STRING', @makeString value, '"', heredoc
		@token ')', ')' if interpolated
		tokens

	token: (tag, value) ->
		@tokens.push [tag, value, @line]

	tag: (index, tag) ->
		(tok = last @tokens, index) and if tag then tok[0] = tag else tok[0]

	value: (index, val) ->
		(tok = last @tokens, index) and if val then tok[1] = val else tok[1]

	unfinished: ->
		LINE_CONTINUER  = /// ^ \s* (?: , | \??\.(?![.\d]) | :: ) ///
		LINE_CONTINUER.test(@chunk) or
		@tag() in ['\\', '.', '?.', 'UNARY', 'MATH', '+', '-', 'SHIFT', 'RELATION'
							 'COMPARE', 'LOGIC', 'COMPOUND_ASSIGN', 'THROW', 'EXTENDS']

	escapeLines: (str, heredoc) ->
		MULTILINER = /\n/g
		str.replace MULTILINER, if heredoc then '\\n' else ''

	makeString: (body, quote, heredoc) ->
		return quote + quote unless body
		body = body.replace /\\([\s\S])/g, (match, contents) ->
			if contents in ['\n', quote] then contents else match
		body = body.replace /// #{quote} ///g, '\\$&'
		quote + @escapeLines(body, heredoc) + quote