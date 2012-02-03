module.exports =
	ALIASES:
		ll: 'ls -l'
	HISTORY_FILE: process.env.HOME + '/.coffee_history'
	HISTORY_FILE_SIZE: 10000 # TODO: implement this
	HISTORY_SIZE: 300
	SHELL_PROMPT_CONTINUATION: '......> '.green
console.log "starting up"