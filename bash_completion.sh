_mkimage_sh()
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
} && complete -F _mkimage_sh ./mkimage.sh


# remove : from wordbreaks as a workaround for silly readline behaviour
# see https://tiswww.case.edu/php/chet/bash/FAQ
# E13) Why does filename completion misbehave if a colon appears in the filename?
COMP_WORDBREAKS=${COMP_WORDBREAKS//:}

_podman_image_list()
{
	podman image list --format '{{range .Names}}{{.}}{{println}}{{end}}{{.Id}}' \
		| sed -e 's:^localhost/::'
}
_podman_partial_image_sh()
{
	local cur prev words cword split
	_init_completion -n ':' || return
	case "$prev" in
	-o|--output)
		_filedir 
		return
		;;
	-b|--base)
		COMPREPLY=($(compgen -W "$(_podman_image_list)" -- "$cur"))
		return
		;;
	-R|--rename)
		return
		;;
	esac

	if [[ $cur == -* ]]; then
		COMPREPLY=($(compgen -W "-b --base -o --output -R --rename" -- "$cur"))
		return
	fi

	COMPREPLY=($(compgen -W "$(_podman_image_list)" -- "$cur"))
	__ltrim_colon_completions
} && complete -F _podman_partial_image_sh ./podman_partial_image.sh

_hawkbit_create-update_sh()
{
	local cur prev words cword split
	_init_completion || return
	COMPREPLY=($(compgen -W '--new --failed --start --no-rollout --keep-tmpdir' -- "$cur"))
	_filedir 'swu'
} && complete -F _hawkbit_create-update_sh ./create-update.sh \
  && complete -F _hawkbit_create-update_sh ./hawkbit/create-update.sh
