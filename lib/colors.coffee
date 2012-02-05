styles = 
	# styles
	'bold'      : (s) -> ['\033[1m', s, '\033[22m'].join()
	'faint'     : (s) -> ['\033[2m', s, '\033[22m'].join()
	'italic'    : (s) -> ['\033[3m', s, '\033[23m'].join()
	'underline' : (s) -> ['\033[4m', s, '\033[24m'].join()
	'inverse'   : (s) -> ['\033[7m', s, '\033[27m'].join()
	'color'     : (s) ->

colors =
	#colors
	'black'     : ['\033[30m', '\033[39m']
	'red'       : ['\033[31m', '\033[39m']
	'green'     : ['\033[32m', '\033[39m']
	'yellow'    : ['\033[33m', '\033[39m']
	'blue'      : ['\033[34m', '\033[39m']
	'magenta'   : ['\033[35m', '\033[39m']
	'cyan'      : ['\033[36m', '\033[39m']
	'white'     : ['\033[37m', '\033[39m']


	'grey'      : ['\033[90m', '\033[39m']
###
	
addProperty = (color, func) ->
	module.exports[color] = (str) => func(str) 
	String::__defineGetter__ color, func

for style, codes of styles


	addProperty
	(str, style) ->
		styles[style][0] + str + styles[style][1]
	addProperty(style, function () {
		return stylize(this, style);
	});
});

function sequencer(map) {
	return function () {
		if (!isHeadless) {
			return this.replace(/( )/, '$1');
		}
		var exploded = this.split("");
		var i = 0;
		exploded = exploded.map(map);
		return exploded.join("");
	}
}

var rainbowMap = (function () {
	var rainbowColors = ['red','yellow','green','blue','magenta']; //RoY G BiV
	return function (letter, i, exploded) {
		if (letter == " ") {
			return letter;
		} else {
			return stylize(letter, rainbowColors[i++ % rainbowColors.length]);
		}
	}
})();

exports.addSequencer = function (name, map) {
	addProperty(name, sequencer(map));
}

exports.addSequencer('rainbow', rainbowMap);
exports.addSequencer('zebra', function (letter, i, exploded) {
	return i % 2 === 0 ? letter : letter.inverse;
});

exports.setTheme = function (theme) {
	Object.keys(theme).forEach(function(prop){
		addProperty(prop, function(){
			return exports[theme[prop]](this);
		});
	});
}


addProperty('stripColors', function() {
	return ("" + this).replace(/\u001b\[\d+m/g,'');
});
###