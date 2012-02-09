colormap = 
	black : 16
	red : 196
	green : 46
	yellow : 226
	blue : 21
	magenta : 201
	cyan : 51
	white : 231
	azurite : 17
	caperBerry : 22
	rainforest : 23 #, 29, 30, 36, 37]
	darkeningSky : 25 #, 31, 32]
	ladybug : 52 # 124, 160]
	beet : 53
	mossyRock : 58 # , 64, 100
	magnetite : 59
	purpleHeliotrope : 60
	bluebird : 62
	bonsai : 65
	hosta : 66
	araucanaTeal : 73 #, 86]
	lagoon : 80
	cloudlessDay : 81 #, 87, 123]
	cornucopia : 89 #, 90, 125, 197, 205]
	grahamCrackerCrust : 94
	ohioBuckeye : 95
	grapeJellyBean : 96 #, 133]
	dill : 101
	zinc : 102
	darkRed: 88
	tempest : 103
	bayLeaf : 107
	wintergreen : 108
	geyser : 109
	stratosphere : 111 #, 147, 153, 159]
	seaGlass : 121 # , 151, 158
	lagoon : 122
	yam : 130 #, 136, 166]
	watermelon : 131
	heatheredMoor : 138
	violetAster : 139
	sultana : 143 #, 186]
	saguaro : 144
	wintersDay : 145
	aegeanBlue : 152
	auroraBorealis : 157
	terraRosa : 167
	lightSandstone : 174
	cornichon : 141 #, 177, 183]
	larkspur : 181
	yellowMagnolia : 185
	lemongrass : 187
	heavyGoose : 188
	loveMist : 189
	auroraBorealis : 193
	beryl : 194
	heavenlyBlue : 195
	pencil : 172 #, 178 #, 202, 208, 214, 215]
	terraRosa : 203 #, 204]
	butterscotch : 173 #, 209]
	peony : 210
	hollyhockPink : 175 #, 211, 212]
	punch : 216
	sugaredPansyPink : 217 #, 218]
	carnation : 219 #, 224, 225]
	eggYolk : 221 #, 227]
	cornbread : 222
	custard : 223
	mimosa : 192 #, 228, 229]
	lemonIce : 230
	picketFence : 231
for i in [232..255]
	colormap["grey" + (i-232)] = i

styles = 
	'bold': (s) -> "\033[1m#{s}\033[22m"
	'italic': (s) -> "\033[3m#{s}\033[23m"
	'underline': (s) -> "\033[4m#{s}\033[24m"
	'inverse': (s) -> "\033[7m#{s}\033[27m"
	'removeStyle': (s) -> s.replace(/\u001b\[(\d+;?)+m/g,'')

for colorname, colornum of colormap
	 do (colorname, colornum)->
		 if colorname isnt colornum
			 styles["#{colorname}"] = (s) -> "\033[38;5;#{colornum}m#{s}\033[39m" #"\033[#{offset+30}m#{s}\033[39m"
			 styles["bg#{colorname}"] = (s) -> "\033[48;5;#{colornum}m#{s}\033[49m" #"\033[#{offset+40}m#{s}\033[49m"
			 module.exports["#{colorname}"] = "\033[38;5;#{colornum}m" #{@}\033[39m" #"\033[#{offset+30}m"
			 module.exports["bg#{colorname}"] = "\033[48;5;#{colornum}m"#{@}\033[49m" # "\033[#{offset+40}m"

for prop, func of styles
	do (prop, func) =>
		String::__defineGetter__ prop, -> func(@)

String::color = (c) -> "\033[38;5;#{c}m#{@}\033[39m"
String::bgcolor = (c) -> "\033[48;5;#{c}m#{@}\033[49m"
String::lighten = (degree = 1) -> 
	this.replace /(\u001b\[(?:38|48);5;)(\d+)m/g, (str, beginning, color) ->
		if 16 <= color <= 231
			b = (color - 16) % 6 + 1
			g = Math.floor((color - 16) / 6) % 6 + 1
			r = Math.floor((color - 16) / 36) % 6 + 1
			while b <= 5 and g <= 5 and r <= 5 and degree-- > 0
				color = ((b++) + (g++)*6 + (r++)*36 + 16)
		else if 232 <= color < 255
			shl.displayDebug [color,degree]
			color = Math.min(254, color + degree)
			shl.displayDebug [color,degree]
		shl.displayDebug [color,degree]
		beginning + color + "m"
String::darken = (degree = 1) -> 
	this.replace /(\u001b\[(?:38|48);5;)(\d+)m/g, (str, beginning, color) ->
		if 16 <= color <= 231
			b = (color - 16) % 6 - 1
			g = Math.floor((color - 16) / 6) % 6 - 1
			r = Math.floor((color - 16) / 36) % 6 - 1
			while b >= 0 and g >= 0 and r >= 0 and degree-- > 0
				color = ((b--) + (g--)*6 + (r--)*36 + 16)
		else if 232 < color <= 255
			color = Math.max(232, color - degree)
		shl.displayDebug [color,degree]
		beginning + color + "m"
module.exports.color = (c) -> "\033[38;5;#{c}m"
module.exports.bgcolor = (c) -> "\033[48;5;#{c}m"
		

module.exports.reset = "\033[0m"
String::truncStyle = (i) ->
	realchar = 
		///
			(?:  \u001b\[\d+;?m  )+ [\s\S]
			| [\s\S]
		///g
	("#{this.match(realchar)[...i].join('')}\033[0m")

# hexes = [
#    '000000', '800000', '008000', '808000', '000080', '800080', '008080', 'c0c0c0', 
#    '808080', 'ff0000', '00ff00', 'ffff00', '0000ff', 'ff00ff', '00ffff', 'ffffff', 
#    '000000', '00005f', '000087', '0000af', '0000d7', '0000ff', '005f00', '005f5f', 
#    '005f87', '005faf', '005fd7', '005fff', '008700', '00875f', '008787', '0087af', 
#    '0087d7', '0087ff', '00af00', '00af5f', '00af87', '00afaf', '00afd7', '00afff', 
#    '00d700', '00d75f', '00d787', '00d7af', '00d7d7', '00d7ff', '00ff00', '00ff5f', 
#    '00ff87', '00ffaf', '00ffd7', '00ffff', '5f0000', '5f005f', '5f0087', '5f00af', 
#    '5f00d7', '5f00ff', '5f5f00', '5f5f5f', '5f5f87', '5f5faf', '5f5fd7', '5f5fff', 
#    '5f8700', '5f875f', '5f8787', '5f87af', '5f87d7', '5f87ff', '5faf00', '5faf5f', 
#    '5faf87', '5fafaf', '5fafd7', '5fafff', '5fd700', '5fd75f', '5fd787', '5fd7af', 
#    '5fd7d7', '5fd7ff', '5fff00', '5fff5f', '5fff87', '5fffaf', '5fffd7', '5fffff', 
#    '870000', '87005f', '870087', '8700af', '8700d7', '8700ff', '875f00', '875f5f', 
#    '875f87', '875faf', '875fd7', '875fff', '878700', '87875f', '878787', '8787af', 
#    '8787d7', '8787ff', '87af00', '87af5f', '87af87', '87afaf', '87afd7', '87afff', 
#    '87d700', '87d75f', '87d787', '87d7af', '87d7d7', '87d7ff', '87ff00', '87ff5f', 
#    '87ff87', '87ffaf', '87ffd7', '87ffff', 'af0000', 'af005f', 'af0087', 'af00af', 
#    'af00d7', 'af00ff', 'af5f00', 'af5f5f', 'af5f87', 'af5faf', 'af5fd7', 'af5fff', 
#    'af8700', 'af875f', 'af8787', 'af87af', 'af87d7', 'af87ff', 'afaf00', 'afaf5f', 
#    'afaf87', 'afafaf', 'afafd7', 'afafff', 'afd700', 'afd75f', 'afd787', 'afd7af', 
#    'afd7d7', 'afd7ff', 'afff00', 'afff5f', 'afff87', 'afffaf', 'afffd7', 'afffff', 
#    'd70000', 'd7005f', 'd70087', 'd700af', 'd700d7', 'd700ff', 'd75f00', 'd75f5f', 
#    'd75f87', 'd75faf', 'd75fd7', 'd75fff', 'd78700', 'd7875f', 'd78787', 'd787af', 
#    'd787d7', 'd787ff', 'd7af00', 'd7af5f', 'd7af87', 'd7afaf', 'd7afd7', 'd7afff', 
#    'd7d700', 'd7d75f', 'd7d787', 'd7d7af', 'd7d7d7', 'd7d7ff', 'd7ff00', 'd7ff5f', 
#    'd7ff87', 'd7ffaf', 'd7ffd7', 'd7ffff', 'ff0000', 'ff005f', 'ff0087', 'ff00af', 
#    'ff00d7', 'ff00ff', 'ff5f00', 'ff5f5f', 'ff5f87', 'ff5faf', 'ff5fd7', 'ff5fff', 
#    'ff8700', 'ff875f', 'ff8787', 'ff87af', 'ff87d7', 'ff87ff', 'ffaf00', 'ffaf5f', 
#    'ffaf87', 'ffafaf', 'ffafd7', 'ffafff', 'ffd700', 'ffd75f', 'ffd787', 'ffd7af', 
#    'ffd7d7', 'ffd7ff', 'ffff00', 'ffff5f', 'ffff87', 'ffffaf', 'ffffd7', 'ffffff', 
#    '080808', '121212', '1c1c1c', '262626', '303030', '3a3a3a', '444444', '4e4e4e', 
#    '585858', '626262', '6c6c6c', '767676', '808080', '8a8a8a', '949494', '9e9e9e', 
#    'a8a8a8', 'b2b2b2', 'bcbcbc', 'c6c6c6', 'd0d0d0', 'dadada', 'e4e4e4', 'eeeeee'
#   ]
