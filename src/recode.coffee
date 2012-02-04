{count, starts, compact, last} = require('coffee-script').helpers
RESERVED = ['case', 'default', 'function', 'var', 'void', 'with', 'const', 'let', 'enum', 'export', 'import', 'native', '__hasProp', '__extends', '__slice', '__bind', '__indexOf']
JS_KEYWORDS = ['true', 'false', 'null', 'this', 'new', 'delete', 'typeof', 'in', 'instanceof', 'return', 'throw', 'break', 'continue', 'debugger', 'if', 'else', 'switch', 'for', 'while', 'do', 'try', 'catch', 'finally', 'class', 'extends', 'super']
JS_FORBIDDEN = ['true', 'false', 'null', 'this', 'new', 'delete', 'typeof', 'in', 'instanceof', 'return', 'throw', 'break', 'continue', 'debugger', 'if', 'else', 'switch', 'for', 'while', 'do', 'try', 'catch', 'finally', 'class', 'extends', 'super', 'case', 'default', 'function', 'var', 'void', 'with', 'const', 'let', 'enum', 'export', 'import', 'native', '__hasProp', '__extends', '__slice', '__bind', '__indexOf']
COFFEE_KEYWORDS = ['undefined', 'then', 'unless', 'until', 'loop', 'of', 'by', 'when']
COFFEE_ALIAS_MAP = and: '&&', or: '||', is: '==', isnt: '!=', not: '!', yes: 'true', no: 'false', on: 'true', off: 'false'
COFFEE_ALIASES  = ['and', 'or', 'is', 'isnt', 'not', 'yes', 'no', 'on', 'off']
COFFEE_KEYWORDS = ['undefined', 'then', 'unless', 'until', 'loop', 'of', 'by', 'when', 'and', 'or', 'is', 'isnt', 'not', 'yes', 'no', 'on', 'off']


exports.Recode = (code) ->
	exectmp = ''
	indented = 0
	tokens = (new Lexer).tokenize code, {rewrite: on}
	output = []
	for i in [0...tokens.length]
		[lex,val] = tokens[i]
		echo tokens[i]
		if tokens[i-1]?[0] in ['TERMINATOR', 'INDENT', 'OUTDENT']
			output.push('\t') for t in [0...indented] 
		
		switch lex
			when 'BUILTIN'
				output.push "#{val}#{if tokens[i+1]?[0] is 'TERMINATOR' then '()' else ''}"
			when 'PARAM'
				output.push "#{val}#{if tokens[i+1]?[0] in ['TERMINATOR', 'CALL_END', ')'] then '' else ','}"
			when 'BINARIES', 'FILEPATH'
				exectmp += val
				if tokens[i+1]?[0] in ['TERMINATOR', 'OUTDENT', 'CALL_END']
					output.push "shl.execute(#{Lexer.prototype.makeString(exectmp, '"', no)})"
					exectmp = ''
				else exectmp += " "
			when 'ARG', 'PIPE'
				exectmp += val
				if tokens[i+1]?[0] in ['TERMINATOR', 'CALL_END', ")"]
					output.push "shl.execute(#{Lexer.prototype.makeString(exectmp, '"', no)})"
					exectmp = ''
				else exectmp += " "
			when 'CALL_START', 'CALL_END'
				if tokens[i-1][0] not in ['BINARIES', 'FILEPATH', 'ARG', 'PIPE']
					output.push val
			#			when '=', '(', ')', '{', '}', '[', ']', ':', '.', '->', ',', '..', '...', '-', '+'
			#					, 'BOOL', 'NUMBER', 'MATH', 'STRING', 'IDENTIFIER', 'THIS', '@'
			#					, 'INDEX_START', 'INDEX_END', 'CALL_START', 'CALL_END', 'PARAM_START', 'PARAM_END'
			#					, 'FOR', 'FORIN', 'FOROF', 'OWN', 'IF', 'POST_IF', 'SWITCH', 'WHEN', 'EXTENDS'
			#				output.push val
			#when 'IDENTIFIER'
			#	output.push val
			when 'TERMINATOR'
				output.push ""
			when 'INDENT'
				if tokens[i].fromThen
					output.push "then " 
				indented += tokens[i][1]
			when 'OUTDENT'
				indented -= tokens[i][1]
			else 
				output.push val
		
		if tokens[i+1]?[0] not in ['CALL_START'] and tokens[i].spaced?
			output.push ' '
		if tokens[i].newLine?
			output.push '\n' 
	(output.join(''))


class Lexer
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
			i += @pathToken() or
				@identifierToken() or
				@commentToken() or
				@whitespaceToken() or
				@lineToken() or
				@heredocToken() or
				@stringToken() or
				@numberToken() or		
				@literalToken()
		@closeIndentation()
		
		# Rewrite
		if opts.rewrite
			@removeLeadingNewlines()
			@removeMidExpressionNewlines()
			@closeOpenCalls()
			@closeOpenIndexes()
			@addImplicitIndentation()
			@tagPostfixConditionals()
			@addImplicitBraces()
			@addImplicitParentheses()
			@ensureBalance()
			@rewriteClosingParens()
		
		(@tokens)

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
		
		prev = last @tokens
		return 0 if prev and (prev[0] in (if prev.spaced then NOT_FILEPATH else NOT_SPACED_FILEPATH))
		if @chunk in ['.', '..']
			if prev and prev[0] in ['BINARIES', 'FILEPATH', 'ARG', 'IDENTIFIER']
				@token 'ARG', @chunk
			else if prev and prev[0] in ['BUILTIN']
				@token 'PARAM', @makeString @chunk, '"', no
			else
				@token 'FILEPATH', @makeString @chunk, '"', no
			return @chunk.length
		return 0 unless match = FILEPATH.exec @chunk
		[filepath] = match
		
		if prev and prev[1] in ['|', '<', '>', '<<', '>>', '&']
			@tokens.pop()
			@token 'PIPE', prev[1]
			@token 'ARG', filepath
			return filepath.length
		
		if prev and prev[0] in ['BINARIES', 'FILEPATH', 'ARG', 'IDENTIFIER']
			@token 'ARG', filepath
			return filepath.length
		
		if prev and prev[0] in ['BUILTIN']
			@token 'PARAM', @makeString filepath, '"', no
			return filepath.length
		
		@token 'FILEPATH', @makeString filepath, '"', no
		(filepath.length)

	identifierToken: ->
		IDENTIFIER = /// ^
			( [$A-Za-z_\x7f-\uffff][$=\w\x7f-\uffff]* )
			( [^\n\S]* : (?!:) )?  # Is this a property name?
		///
		#SHELL_CONTROL = ['&', '|', '<', '>', '<<', '>>', '*', '~', '!', '-', '--', '/', '%', '+', '.', '$', '`', '\'', '"' ]
		RELATION = ['IN', 'OF', 'INSTANCEOF']
		LINE_BREAK = ['INDENT', 'OUTDENT', 'TERMINATOR']
		UNARY   = ['!', '~', 'NEW', 'TYPEOF', 'DELETE', 'DO']
		return 0 unless match = IDENTIFIER.exec @chunk
		[input, id, colon] = match

		prev = last @tokens
		if prev?[0] in ['BINARIES', 'FILEPATH', 'ARG']
			arg = id
			@token 'ARG', arg
			return id.length
			
		if prev?[0] in ['BUILTIN', 'PARAM']
			@token 'PARAM', @makeString id, '"', no
			return id.length
		
		if prev?[0] in ['-', '--', '+'] and @tokens[@tokens.length-2]?[0] in ['BINARIES', 'BUILTIN', 'FILEPATH', 'ARG']
			arg = prev[0]+id
			@tokens.pop()
			@token 'ARG', arg
			return id.length
		
		if prev?[1] in ['|', '<', '>', '<<', '>>', '&'] and @tokens[@tokens.length-2]?[0] in ['BINARIES', 'BUILTIN', 'FILEPATH', 'ARG']
			@tokens.pop()
			@token 'PIPE', prev[1]
			@token 'ARG', id
			return id.length
		
		if prev?[0] in ['.'] and @tokens[@tokens.length-2]?[0] in ['BINARIES', 'BUILTIN', 'FILEPATH', 'ARG']
			arg = @tokens[@tokens.length-2][1]+prev[0]+id
			@tokens.pop()
			@tokens.pop()
			@token 'ARG', arg
			return id.length
		
		if prev?[0] not in ['.'] and builtin.hasOwnProperty id
			cmd = "builtin.#{id}"
			@token 'BUILTIN', cmd
			return id.length
			
		if prev?[0] not in ['.', '\\', '='] and aliases.hasOwnProperty id
			alias = (aliases[id].split(' '))[0]
			if binaries.hasOwnProperty alias
				if prev?[1] in ['|', '<', '>', '<<', '>>', '&']
					@tokens.pop()
					@token 'PIPE', prev[1]
				cmd = "#{binaries[alias]}/#{aliases[id]}"
				@token 'BINARIES', cmd
				return id.length
				
		if prev?[0] not in ['.', '\\', '='] and binaries.hasOwnProperty id
			if prev?[1] in ['|', '<', '>', '<<', '>>', '&']
				@tokens.pop()
				@token 'PIPE', prev[1]

			cmd = "#{binaries[id]}/#{id}"
			@token 'BINARIES', cmd
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
		if (prev = last @tokens) and prev[0] in ['BINARIES', 'FILEPATH', 'ARG']
			@token 'ARG', number
			return number.length
		if (prev = last @tokens) and prev[0] in ['BUILTIN', 'PARAM']
			@token 'PARAM', @makeString number, '"', no
			return number.length
		
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
		
		
		
		
	## Rewriter

	scanTokens: (block) ->
		{tokens} = this
		i = 0
		i += block.call this, token, i, tokens while token = tokens[i]
		true

	detectEnd: (i, condition, action) ->
		EXPRESSION_START = [ '(', '[', '{', 'INDENT', 'CALL_START', 'PARAM_START', 'INDEX_START' ]
		EXPRESSION_END   = [ ')', ']', '}', 'OUTDENT', 'CALL_END', 'PARAM_END', 'INDEX_END' ]
		{tokens} = this
		levels = 0
		while token = tokens[i]
			return action.call this, token, i     if levels is 0 and condition.call this, token, i
			return action.call this, token, i - 1 if not token or levels < 0
			if token[0] in EXPRESSION_START
				levels += 1
			else if token[0] in EXPRESSION_END
				levels -= 1
			i += 1
		i - 1

	removeLeadingNewlines: ->
		break for [tag], i in @tokens when tag isnt 'TERMINATOR'
		@tokens.splice 0, i if i

	removeMidExpressionNewlines: ->
		EXPRESSION_CLOSE = [ ')', ']', '}', 'OUTDENT', 'CALL_END', 'PARAM_END', 'INDEX_END', 'CATCH', 'WHEN', 'ELSE', 'FINALLY']
		@scanTokens (token, i, tokens) ->
			return 1 unless token[0] is 'TERMINATOR' and @rtag(i + 1) in EXPRESSION_CLOSE
			tokens.splice i, 1
			0

	closeOpenCalls: ->
		condition = (token, i) ->
			token[0] in [')', 'CALL_END'] or
			token[0] is 'OUTDENT' and @rtag(i - 1) is ')'
		action = (token, i) ->
			@tokens[if token[0] is 'OUTDENT' then i - 1 else i][0] = 'CALL_END'
		@scanTokens (token, i) ->
			@detectEnd i + 1, condition, action if token[0] is 'CALL_START'
			1

	closeOpenIndexes: ->
		condition = (token, i) -> token[0] in [']', 'INDEX_END']
		action    = (token, i) -> token[0] = 'INDEX_END'
		@scanTokens (token, i) ->
			@detectEnd i + 1, condition, action if token[0] is 'INDEX_START'
			1

	addImplicitBraces: ->
		EXPRESSION_START = [ '(', '[', '{', 'INDENT', 'CALL_START', 'PARAM_START', 'INDEX_START' ]
		EXPRESSION_END   = [ ')', ']', '}', 'OUTDENT', 'CALL_END', 'PARAM_END', 'INDEX_END' ]
		stack       = []
		start       = null
		startIndent = 0
		condition = (token, i) ->
			[one, two, three] = @tokens[i + 1 .. i + 3]
			return false if 'HERECOMMENT' is one?[0]
			[tag] = token
			(tag in ['TERMINATOR', 'OUTDENT'] and
				not (two?[0] is ':' or one?[0] is '@' and three?[0] is ':')) or
				(tag is ',' and one and
					one[0] not in ['FILEPATH', 'IDENTIFIER', 'NUMBER', 'STRING', '@', 'TERMINATOR', 'OUTDENT'])
		action = (token, i) ->
			tok = ['}', '}', token[2]]
			tok.generated = yes
			@tokens.splice i, 0, tok
		@scanTokens (token, i, tokens) ->
			if (tag = token[0]) in EXPRESSION_START
				stack.push [(if tag is 'INDENT' and @rtag(i - 1) is '{' then '{' else tag), i]
				return 1
			if tag in EXPRESSION_END
				start = stack.pop()
				return 1
			return 1 unless tag is ':' and
				((ago = @rtag i - 2) is ':' or stack[stack.length - 1]?[0] isnt '{')
			stack.push ['{']
			idx =  if ago is '@' then i - 2 else i - 1
			idx -= 2 while @rtag(idx - 2) is 'HERECOMMENT'
			value = new String('{')
			value.generated = yes
			tok = ['{', value, token[2]]
			tok.generated = yes
			tokens.splice idx, 0, tok
			@detectEnd i + 2, condition, action
			2

	addImplicitParentheses: ->
		IMPLICIT_FUNC    = ['IDENTIFIER', 'SUPER', ')', 'CALL_END', ']', 'INDEX_END', '@', 'THIS', 'BUILTIN', 'FILEPATH', 'BINARIES']
		IMPLICIT_CALL    = [
			'IDENTIFIER', 'NUMBER', 'STRING', 'JS', 'REGEX', 'NEW', 'PARAM_START', 'CLASS'
			'IF', 'TRY', 'SWITCH', 'THIS', 'BOOL', 'UNARY', 'SUPER'
			'@', '->', '=>', '[', '(', '{', '--', '++', 'FILEPATH', 'BINARIES', 'BUILTIN', 'ARG', 'PARAM'
		]
		IMPLICIT_UNSPACED_CALL = ['+', '-']
		IMPLICIT_BLOCK   = ['->', '=>', '{', '[', ',']
		IMPLICIT_END     = ['POST_IF', 'FOR', 'WHILE', 'UNTIL', 'WHEN', 'BY', 'LOOP', 'TERMINATOR']
		LINEBREAKS       = ['TERMINATOR', 'INDENT', 'OUTDENT']
	
		noCall = no
		action = (token, i) ->
			idx = if token[0] is 'OUTDENT' then i + 1 else i
			@tokens.splice idx, 0, ['CALL_END', ')', token[2]]
		@scanTokens (token, i, tokens) ->
			tag     = token[0]
			noCall  = yes if tag in ['CLASS', 'IF']
			[prev, current, next] = tokens[i - 1 .. i + 1]
			callObject  = not noCall and tag is 'INDENT' and
										next and next.generated and next[0] is '{' and
										prev and prev[0] in IMPLICIT_FUNC
			seenSingle  = no
			seenControl = no
			noCall      = no if tag in LINEBREAKS
			token.call  = yes if prev and not prev.spaced and tag is '?'
			return 1 if token.fromThen
			return 1 unless callObject or
				prev?.spaced and (prev.call or prev[0] in IMPLICIT_FUNC) and
				(tag in IMPLICIT_CALL or not (token.spaced or token.newLine) and tag in IMPLICIT_UNSPACED_CALL)
			tokens.splice i, 0, ['CALL_START', '(', token[2]]
			@detectEnd i + 1, (token, i) ->
				[tag] = token
				return yes if not seenSingle and token.fromThen
				seenSingle  = yes if tag in ['IF', 'ELSE', 'CATCH', '->', '=>']
				seenControl = yes if tag in ['IF', 'ELSE', 'SWITCH', 'TRY']
				return yes if tag in ['.', '?.', '::'] and @rtag(i - 1) is 'OUTDENT'
				not token.generated and @rtag(i - 1) isnt ',' and (tag in IMPLICIT_END or
				(tag is 'INDENT' and not seenControl)) and
				(tag isnt 'INDENT' or
				 (@rtag(i - 2) isnt 'CLASS' and @rtag(i - 1) not in IMPLICIT_BLOCK and
					not ((post = @tokens[i + 1]) and post.generated and post[0] is '{')))
			, action
			prev[0] = 'FUNC_EXIST' if prev[0] is '?'
			2

	addImplicitIndentation: ->
		SINGLE_LINERS    = ['ELSE', '->', '=>', 'TRY', 'FINALLY', 'THEN']
		SINGLE_CLOSERS   = ['TERMINATOR', 'CATCH', 'FINALLY', 'ELSE', 'OUTDENT', 'LEADING_WHEN']
	
		@scanTokens (token, i, tokens) ->
			[tag] = token
			if tag is 'TERMINATOR' and @rtag(i + 1) is 'THEN'
				tokens.splice i, 1
				return 0
			if tag is 'ELSE' and @rtag(i - 1) isnt 'OUTDENT'
				tokens.splice i, 0, @indentation(token)...
				return 2
			if tag is 'CATCH' and @rtag(i + 2) in ['OUTDENT', 'TERMINATOR', 'FINALLY']
				tokens.splice i + 2, 0, @indentation(token)...
				return 4
			if tag in SINGLE_LINERS and @rtag(i + 1) isnt 'INDENT' and
				 not (tag is 'ELSE' and @rtag(i + 1) is 'IF')
				starter = tag
				[indent, outdent] = @indentation token
				indent.fromThen   = true if starter is 'THEN'
				indent.generated  = outdent.generated = true
				tokens.splice i + 1, 0, indent
				condition = (token, i) ->
					token[1] isnt ';' and token[0] in SINGLE_CLOSERS and
					not (token[0] is 'ELSE' and starter not in ['IF', 'THEN'])
				action = (token, i) ->
					@tokens.splice (if @rtag(i - 1) is ',' then i - 1 else i), 0, outdent
				@detectEnd i + 2, condition, action
				tokens.splice i, 1 if tag is 'THEN'
				return 1
			return 1

	tagPostfixConditionals: ->
		condition = (token, i) -> token[0] in ['TERMINATOR', 'INDENT']
		@scanTokens (token, i) ->
			return 1 unless token[0] is 'IF'
			original = token
			@detectEnd i + 1, condition, (token, i) ->
				original[0] = 'POST_' + original[0] if token[0] isnt 'INDENT'
			1

	ensureBalance: ->
		pairs = [
			['(', ')']
			['[', ']']
			['{', '}']
			['INDENT', 'OUTDENT'],
			['CALL_START', 'CALL_END']
			['PARAM_START', 'PARAM_END']
			['INDEX_START', 'INDEX_END']
		]
		levels   = {}
		openLine = {}
		for token in @tokens
			[tag] = token
			for [open, close] in pairs
				levels[open] |= 0
				if tag is open
					openLine[open] = token[2] if levels[open]++ is 0
				else if tag is close and --levels[open] < 0
					throw Error "too many #{token[1]} on line #{token[2] + 1}"
		for open, level of levels when level > 0
			throw Error "unclosed #{ open } on line #{openLine[open] + 1}"
		this

	rewriteClosingParens: ->
		INVERSES = 
			')': '(', '(': ')',
			']': '[', '[': ']',
			'}': '{', '{': '}',
			OUTDENT: 'INDENT', INDENT: 'OUTDENT',
			CALL_END: 'CALL_START', CALL_START: 'CALL_END',
			PARAM_END: 'PARAM_START', PARAM_START: 'PARAM_END',
			INDEX_END: 'INDEX_START', INDEX_START: 'INDEX_END',
		EXPRESSION_START = [ '(', '[', '{', 'INDENT', 'CALL_START', 'PARAM_START', 'INDEX_START' ]
		EXPRESSION_END   = [ ')', ']', '}', 'OUTDENT', 'CALL_END', 'PARAM_END', 'INDEX_END' ]
		
		stack = []
		debt  = {}
		debt[key] = 0 for key of INVERSES
		@scanTokens (token, i, tokens) ->
			if (tag = token[0]) in EXPRESSION_START
				stack.push token
				return 1
			return 1 unless tag in EXPRESSION_END
			if debt[inv = INVERSES[tag]] > 0
				debt[inv] -= 1
				tokens.splice i, 1
				return 0
			match = stack.pop()
			mtag  = match[0]
			oppos = INVERSES[mtag]
			return 1 if tag is oppos
			debt[mtag] += 1
			val = [oppos, if mtag is 'INDENT' then match[1] else oppos]
			if @rtag(i + 2) is mtag
				tokens.splice i + 3, 0, val
				stack.push match
			else
				tokens.splice i, 0, val
			1

	indentation: (token) ->
		[['INDENT', 2, token[2]], ['OUTDENT', 2, token[2]]]

	rtag: (i) -> @tokens[i]?[0]
