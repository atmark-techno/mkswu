_mkswu()
{
	local cur prev words cword split
	_init_completion || return
	case "$prev" in
	-o|--out)
		_filedir
		return
		;;
	-c|--config)
		_filedir 'conf'
		return
		;;
	esac

	COMPREPLY=($(compgen -W '-o --out -c --config' -- "$cur"))
	_filedir 'desc'
} && complete -F _mkswu mkswu
