_hawkbit-create-update_sh()
{
	local cur prev words cword split
	_init_completion || return
	COMPREPLY=($(compgen -W '--new --failed --start --no-rollout --keep-tmpdir' -- "$cur"))
	_filedir 'swu'
} && complete -F _hawkbit_create-update_sh hawkbit-create-update.sh \
