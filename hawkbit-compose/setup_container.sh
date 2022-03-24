#!/bin/bash

## shellcheck doesn't understand indirect variable usage (prompt/save helpers)
## disable this check globally...
# shellcheck disable=SC2034


# TEXTDOMAIN / TEXTDOMAINDIR need to be set at toplevel or bash ignores them
SCRIPT_DIR="$(realpath -P "$0")" || error $"Could not get script dir"
SCRIPT_BASE="${0##*/}"
[[ "$SCRIPT_DIR" = "/" ]] || SCRIPT_DIR="${SCRIPT_DIR%/*}"
case "$SCRIPT_DIR" in
/usr/share*) :;;
*) TEXTDOMAINDIR="$SCRIPT_DIR/locale";;
esac
TEXTDOMAIN=hawkbit_setup_container

error() {
	printf -- "\nERROR: %s\n" "$@" >&2
	exit 1
}

usage() {
	echo $"Usage: $0 [opts]"
	echo
	echo $"    Prompt questions if required and setup hawkBit docker-compose container"
	echo
	echo $"Options:"
	echo $"  --dir <dir>         directory to use for docker-compose root"
	echo $"  --domain <domain>   domain name to use for https certificate"
	echo $"  --letsencrypt       enable letsencrypt container"
	echo $"  --reset-proxy       reset proxy-related settings"
	echo $"  --reset-users       reset hawkBit users"
	echo $"  --add-user <user>   add extra hawkBit admin user"
	echo $"  --del-user <user>   delete hawkBit user with given name"
}

######################
# management helpers #
######################

assemble_fragments() {
	local dest="$1"
	local destdir
	destdir="$(dirname "$dest")"
	[[ -d "$destdir" ]] || mkdir "$destdir" \
		|| error $"Could not create directory"
	dest="$(realpath "$1")" || error $"realpath failed"
	local name="${1##*/}"
	name="${name#.}"
	local fragment fragment_pattern pattern_matched
	declare -a fragments=( )
	shift
	local tmpdest="$dest.tmp"

	# build a list of all fragments.
	# replicate final component at start of filename for sort
	for fragment in "$FRAGMENTS/$name/"*; do
		[[ -e "$fragment" ]] || continue
		fragments+=( "${fragment##*/}/$fragment" )
	done
	for fragment_pattern; do
		pattern_matched=""
		for fragment in "$FRAGMENTS_SRC/$name/"$fragment_pattern; do
			[[ -e "$fragment" ]] || continue
			pattern_matched=1
			[[ -e "$FRAGMENTS/$name/${fragment##*/}" ]] && continue
			fragments+=( "${fragment##*/}/$fragment" )
		done
		[[ -n "$pattern_matched" ]] \
			|| error $"$fragment_pattern did not match anything in $name source fragments"
	done
	# sort and remove sorting key
	mapfile -d '' -t fragments < <(printf "%s\0" "${fragments[@]}" | sort -z | sed -z -e 's:^[^/]*/::')

	cat <(echo "# This file has been automatically generated, edit fragments instead!") \
			"${fragments[@]}" > "$tmpdest" \
		|| error $"Failed aggregating fragments ${fragments[*]} to $tmpdest"

	# only update if changed
	if cmp -s "$dest" "$tmpdest"; then
		rm -f "$tmpdest"
	else
		mv "$tmpdest" "$dest" \
			|| error $"Failed moving $tmpdest to $dest"
	fi
}

update_template() {
	local file="$1"
	shift
	local src="$FRAGMENTS_SRC/$file" dest="$FRAGMENTS/$file"
	local tmpdest="$dest.tmp"

	[[ -d "${dest%/*}" ]] \
		|| mkdir "${dest%/*}" \
		|| error $"Could not create directory"
	sed -e "1i# This fragment has been automatically generated, do not edit!" \
			"$@" "$src" > "$tmpdest" \
		|| error $"Could not generate $file fragment"

	# only update if changed
	if cmp -s "$dest" "$tmpdest"; then
		rm -f "$tmpdest"
	else
		mv "$tmpdest" "$dest" \
			|| error $"Failed moving $tmpdest to $dest"
	fi
}

gen_pass() {
	local len="${1:-16}"
	tr -cd '[:alnum:]%^&*()!><?/' < /dev/urandom | head -c "$len"
}

# password return as 'pass', which should be made local by caller
prompt_pass() {
	local prompt="$1"
	local confirm
	pass=""
	while [[ -z "$pass" ]]; do
		read -r -s -p "$prompt: " pass
		echo
		if [[ -z "$pass" ]]; then
			echo $"Empty passwords are not allowed"
			continue
		fi
		read -r -s -p $"Confirm password: " confirm
		echo
		if [[ "$pass" != "$confirm" ]]; then
			echo $"Password mismatch"
			pass=""
			continue
		fi
	done
}

save_prompt() {
	local prompt_id="$1"
	local value="${!prompt_id}"
	local reply=""

	if [[ -e "$PROMPT_FILE" ]]; then
		reply=$(awk -F= '$1 == "'"$prompt_id"'" { r=$2 }
				 END { if (r) print r }' "$PROMPT_FILE")
	fi
	case "$reply" in
	"$value") return;;
	"") echo "$prompt_id=$value" >> "$PROMPT_FILE";;
	*) 	if [[ -n "$value" ]]; then
			sed -i -e 's/^\('"$prompt_id"'=\).*/\1'"$value"'/' "$PROMPT_FILE"
		else
			sed -i -e '/^'"$prompt_id"'=/d' "$PROMPT_FILE"
		fi;;
	esac
}

# reply return as '${!prompt_id}', which should be made local
# by the caller if appropriate (that is, prompt_reply MOO "need cows?" will populate $MOO)
prompt_reply() {
	local prompt_id="$1"
	local prompt="$2"
	shift 2
	declare -n reply="$prompt_id"
	local default="$reply"
	local nodefault="${NODEFAULT:-}"

	if [[ -e "$PROMPT_FILE" ]]; then
		reply=$(awk -F= '$1 == "'"$prompt_id"'" { r=$2; seen=1; }
				 END { if (seen) print r; else exit 1; }' "$PROMPT_FILE") \
			&& return
	fi

	# no prompt only queries cached value
	[[ -z "$prompt" ]] && return

	case "$nodefault" in
	"") prompt+=" [$default] ";;
	*) prompt+=" ";;
	esac

	(( $# > 0 )) && printf "%s\n" "$@"
	while true; do
		read -r -p "$prompt" reply
		[[ -n "$reply" ]] || [[ -z "$nodefault" ]] && break
		echo $"A value is required."
	done
	[[ -n "$reply" ]] || reply="$default"
	[[ -n "$NOSAVE" ]] \
		|| echo "$prompt_id=$reply" >> "$PROMPT_FILE"
}

prompt_yesno() {
	local prompt_id="$1"
	local prompt="$2"
	shift 2
	local yesno
	declare -n confirm="$prompt_id"
	local ret=""
	local default="${prompt_id}_DEFAULT"
	local default="${!default:-y}"

	if [[ -z "$confirm" ]] && [[ -e "$PROMPT_FILE" ]]; then
		confirm=$(awk -F= '$1 == "'"$prompt_id"'" { r=$2 }
				  END { if (r) print r }' "$PROMPT_FILE")
	fi
	if [[ -z "$confirm" ]] && [[ -z "$prompt" ]]; then
		confirm="$default"
	fi
	case "$confirm" in
	[Yy]|[Yy][Ee][Ss]|[Tt][Rr][Uu][Ee]|1) return 0;;
	[Nn]|[Nn][Oo]|[Ff][Aa][Ll][Ss][Ee]|0) return 1;;
	*) [[ -n "$prompt" ]] || error $"Invalid value $confirm for $prompt_id used with no prompt!"
	esac

	case "$default" in
	[Yy]|[Yy][Ee][Ss]|[Tt][Rr][Uu][Ee]|1) yesno="[Y/n] ";;
	[Nn]|[Nn][Oo]|[Ff][Aa][Ll][Ss][Ee]|0) yesno="[y/N] ";;
	"") yesno="";;
	*) error $"Invalid default $default for $prompt";;
	esac

	(( $# > 0 )) && printf "%s\n" "$@"
	while :; do
		read -r -p "$prompt $yesno" confirm
		[[ -n "$confirm" ]] || confirm="$default"
		case "$confirm" in
		[Yy]|[Yy][Ee][Ss]|[Tt][Rr][Uu][Ee]|1) ret=0; break;;
		[Nn]|[Nn][Oo]|[Ff][Aa][Ll][Ss][Ee]|0) ret=1; break;;
		esac
		echo $"Please answer with y or n"
	done

	[[ -n "$NOSAVE" ]] \
		|| echo "$prompt_id=$confirm" >> "$PROMPT_FILE"
	return "$ret"
}


#################
# nginx section #
#################

generate_cert() {
	local REVERSE_PROXY_CERT_DAYS=3650

	NODEFAULT=1 prompt_reply REVERSE_PROXY_CERT_DOMAIN \
			$"Certificate domain name:" \
			$"The reverse proxy needs a domain name for the certificate" \
			$"This MUST be the domain name as reachable from devices, so if the" \
			$"url will be https://hawkbit.domain.tld it should be hawkbit.domain.tld" \
			$"and if your url is https://10.1.1.1 then it should be 10.1.1.1"
	if [[ -e "$CERT" ]]; then
		local current_domain
		current_domain=$(openssl x509 -subject -noout -in "$CERT" \
					| sed -ne 's/subject=CN = //p')
		[[ "$current_domain" = "$REVERSE_PROXY_CERT_DOMAIN" ]] && return
		echo $"Certificate domain name changed (found $current_domain, expected $REVERSE_PROXY_CERT_DOMAIN), regenerating"
	fi

	[[ -d "$CONFIG_DIR/data/nginx_certs" ]] \
		|| mkdir "$CONFIG_DIR/data/nginx_certs" \
		|| error $"Could not create directory"

	prompt_reply REVERSE_PROXY_CERT_DAYS $"How long should the certificate be valid (days)?" \
		$"TLS certificate have a lifetime that must be set. If you plan to use let's encrypt" \
		$"this value will only be used until the new certificate is generated and can be left" \
		$"to its default value. Best practice would require generating a new certificate every few years."
	case "$REVERSE_PROXY_CERT_DAYS" in
	*[!0-9]*)
		REVERSE_PROXY_CERT_DAYS=""
		save_prompt REVERSE_PROXY_CERT_DAYS
		error $"certificate validity must be a number of days (only digits)";;
	esac


	# generate self-signed key whatever happens:
	# we will need it to bootstrap the LE setup anyway
	openssl ecparam -name prime256v1 -genkey -noout -out "$PRIVKEY"
	openssl req -new -x509 -key "$PRIVKEY" -out "$CERT" \
		    -days "$REVERSE_PROXY_CERT_DAYS" \
		    -subj "/CN=$REVERSE_PROXY_CERT_DOMAIN"
}

do_check_letsencrypt() {
	# For now we just check if the machine bears the requested ip.
	# reality is a lot more complicated, this check is neither sufficient
	# nor necessary, but should prevent people running letsencrypt blindling
	# in atde.
	local domain_ip
	domain_ip=$(dig "$REVERSE_PROXY_CERT_DOMAIN" +short)
	[[ -n "$domain_ip" ]] || return 1
	[[ "$(echo "$domain_ip" | wc -l)" = 1 ]] || return 1

	ip a | grep -qFw "$domain_ip"
}

check_letsencrypt() {
	local REVERSE_PROXY_LETSENCRYPT_CHECK=""
	local REVERSE_PROXY_LETSENCRYPT_CHECK_DEFAULT=n

	prompt_yesno REVERSE_PROXY_LETSENCRYPT_CHECK && return
	REVERSE_PROXY_LETSENCRYPT_CHECK=""

	if do_check_letsencrypt \
	    || prompt_yesno REVERSE_PROXY_LETSENCRYPT_CHECK $"Continue?" \
			$"Could not verify that this host is suitable for let's encrypt" \
			$"Please check the machine is reachable at $REVERSE_PROXY_CERT_DOMAIN"; then
		REVERSE_PROXY_LETSENCRYPT_CHECK=y
	else
		echo $"Continuing without let's encrypt. Run again with --letsencrypt if you want to add it later."
		REVERSE_PROXY_LETSENCRYPT_CHECK=n
		REVERSE_PROXY_LETSENCRYPT=n
		save_prompt REVERSE_PROXY_LETSENCRYPT
	fi
	save_prompt REVERSE_PROXY_LETSENCRYPT_CHECK
	prompt_yesno REVERSE_PROXY_LETSENCRYPT_CHECK
}

finalize_letsencrypt() {
	local REVERSE_PROXY_LETSENCRYPT_EMAIL="" REVERSE_PROXY_LETSENCRYPT_RUN=""
	local REVERSE_PROXY_LETSENCRYPT_STAGING=""
	local REVERSE_PROXY_LETSENCRYPT_SETUP_DONE=""
	local REVERSE_PROXY_LETSENCRYPT_SETUP_DONE_DEFAULT=n

	prompt_yesno REVERSE_PROXY_LETSENCRYPT \
		|| return 0

	prompt_yesno REVERSE_PROXY_LETSENCRYPT_SETUP_DONE \
		&& return

	# LE already setup. Remove data dir to reconfigure...
	[[ "$(readlink "$CONFIG_DIR/data/nginx_certs/proxy.crt")" \
			= "live/$REVERSE_PROXY_CERT_DOMAIN/fullchain.pem" ]] \
		&& return

	declare -a args=( certbot certonly --agree-tos --key-type ecdsa
			  --webroot -w /var/www -d "$REVERSE_PROXY_CERT_DOMAIN" )
	prompt_reply REVERSE_PROXY_LETSENCRYPT_EMAIL \
			$"Email to use for let's encrypt registration"
	case "$REVERSE_PROXY_LETSENCRYPT_EMAIL" in
	"") args+=( "--register-unsafely-without-email" );;
	*) args+=( "--email" "$REVERSE_PROXY_LETSENCRYPT_EMAIL" );;
	esac
	# hidden option for development
	if prompt_yesno REVERSE_PROXY_LETSENCRYPT_STAGING; then
		args+=( "--staging" )
	fi

	if prompt_yesno REVERSE_PROXY_LETSENCRYPT_RUN \
			$"letsencrypt setup requires running containers once for configuration, run now?"; then
		$SUDO docker-compose up -d mysql hawkbit nginx
		local -i count=0
		while ! curl --fail -s -o /dev/null http://127.0.0.1; do
			sleep 1
			((count++ > 5)) && error $"nginx container not coming up!"
		done
		$SUDO docker-compose run --rm -- certbot "${args[@]}" \
			|| error $"certbot invocation failed"
		$SUDO docker-compose down
		rm -f data/nginx_certs/proxy.crt data/nginx_certs/proxy.key \
			|| error $"Could not remove old certificates"
		ln -s "live/$REVERSE_PROXY_CERT_DOMAIN/fullchain.pem" data/nginx_certs/proxy.crt \
			&& ln -s "live/$REVERSE_PROXY_CERT_DOMAIN/privkey.pem" data/nginx_certs/proxy.key \
			|| error $"Could not make symlink to new certificates"
	else
		echo $"Start containers once and run the following commands:"
		echo
		echo "    $SUDO docker-compose run --rm -- certbot ${args[*]}"
		echo "    rm -f data/nginx_certs/proxy.crt data/nginx_certs/proxy.key"
		echo "    ln -s live/$REVERSE_PROXY_CERT_DOMAIN/fullchain.pem data/nginx_certs/proxy.crt"
		echo "    ln -s live/$REVERSE_PROXY_CERT_DOMAIN/privkey.pem data/nginx_certs/proxy.key"
		echo "    $SUDO docker-compose restart nginx"
		echo
	fi
	REVERSE_PROXY_LETSENCRYPT_SETUP_DONE=y
	save_prompt REVERSE_PROXY_LETSENCRYPT_SETUP_DONE
}

reverse_proxy_reset() {
	[[ -e "$PROMPT_FILE" ]] && sed -i -e '/^REVERSE_PROXY/d' "$PROMPT_FILE"
}


####################################################
# hawkbit config (application.properties) section #
####################################################

hawkbit_add_user() {
	local user="$1"
	local permissions="ALL"
	local pass

	if [[ -z "$RESET_PW" ]] \
	   && [[ -e "$FRAGMENTS/hawkbit_application.properties/users_$user" ]]; then
		return 1
	fi

	case "$user" in
	device) permissions="READ_TARGET_SECURITY_TOKEN,CREATE_TARGET";;
	mkswu)
		permissions="READ_REPOSITORY,UPDATE_REPOSITORY,CREATE_REPOSITORY"
		permissions+=",UPDATE_TARGETS,READ_TARGET,CREATE_ROLLOUT,READ_ROLLOUT"
		prompt_yesno HAWKBIT_USER_MKSWU_ROLLOUT \
				$"Allow user to handle rollouts? (trigger installation requests)" \
			&& permissions+=",HANDLE_ROLLOUT"
		;;
	esac

	prompt_pass $"Password for user $user"
	pass="$(htpasswd -niBC 10 "" <<<"$pass")" \
		|| error $"htpasswd failed for given password - missing command?"
	pass="${pass#:}"

	[[ -d "$FRAGMENTS/hawkbit_application.properties" ]] \
		|| mkdir "$FRAGMENTS/hawkbit_application.properties"\
		|| error $"Could not create directory"

	cat > "$FRAGMENTS/hawkbit_application.properties/users_$user" <<EOF
hawkbit.server.im.users[0].username=$user
hawkbit.server.im.users[0].password={bcrypt}$pass
hawkbit.server.im.users[0].permissions=$permissions
EOF
}

hawkbit_del_user() {
	local user fragment
	echo $"Removing users:"
	printf "%s\n" "$@"
	for user; do
		fragment="$FRAGMENTS/hawkbit_application.properties/users_$user"
		if ! [[ -e "$fragment" ]]; then
			echo "User $user did not exist!"
			continue
		fi
		rm -f "$fragment"
	done
}

hawkbit_reset_users() {
	local f
	echo $"Removing users:"
	for f in "$FRAGMENTS/hawkbit_application.properties/users_"*; do
		[[ -e "$f" ]] || continue
		echo "	${f##*/users_}"
		rm -f "$f"
	done
	[[ -e "$PROMPT_FILE" ]] && sed -i -e '/^HAWKBIT_USER_/d' "$PROMPT_FILE"
}

fix_hawkbit_users_id() {
	local file index=0 i

	for file in "$FRAGMENTS/hawkbit_application.properties/"*; do
		[[ -e "$file" ]] || continue
		grep -qF "hawkbit.server.im.users" "$file" || continue
		i=$(awk -vi=$index -F'\n' '/^hawkbit.server.im.users/ {
				split($0, words, /[][]/);
				uid=words[2];
				if (!(uid in idx)) {
					idx[uid] = i++;
				};
				gsub(/hawkbit.server.im.users\[[^]]\]/, "hawkbit.server.im.users["idx[uid]"]");
			}
			{ print }
			END {
				print length(idx) >"/dev/stderr";
			}' < "$file" 2>&1 > "$file.tmp") \
				|| error $"Could not update user id in hawkBit application.properties"
		if cmp -s "$file" "$file.tmp"; then
			rm -f "$file.tmp"
		else
			mv "$file.tmp" "$file"
		fi
		index=$((index+i))
	done

	((index > 0)) || error $"hawkBit had no user defined, create one first"
}

finalize_hawkbit() {
	fix_hawkbit_users_id
	assemble_fragments "$CONFIG_DIR/data/hawkbit_application.properties" \
			pollingTime update_size rabbitmq "auth_*"
}

##########################
# docker compose section #
##########################

finalize_compose() {
	declare -a compose_yml_fragments=( 00_header 10_mysql "20_hawkbit_*" )

	if prompt_yesno REVERSE_PROXY; then
		compose_yml_fragments+=( 30_nginx )
		prompt_yesno REVERSE_PROXY_LETSENCRYPT \
			&& compose_yml_fragments+=( 40_certbot )
	fi
	[[ -e "$CONFIG_DIR/data/mysql_utf8.cnf" ]] \
		&& cmp -s "$FRAGMENTS_SRC/mysql_utf8.cnf" "$CONFIG_DIR/data/mysql_utf8.cnf" \
		|| cp "$FRAGMENTS_SRC/mysql_utf8.cnf" "$CONFIG_DIR/data/mysql_utf8.cnf" \
		|| error $"Could not copy file"

	assemble_fragments "$CONFIG_DIR/docker-compose.yml" "${compose_yml_fragments[@]}"


	if ! [[ -e "$FRAGMENTS/env/mysql" ]]; then
		[[ -d "$FRAGMENTS/env" ]] || mkdir "$FRAGMENTS/env" \
			|| error $"Could not create directory"
		cat > "$FRAGMENTS/env/mysql" <<EOF
MYSQL_PASSWORD=$(gen_pass)
MYSQL_ROOT_PASSWORD=$(gen_pass)
EOF
	fi
	assemble_fragments "$CONFIG_DIR/.env"
}

#######################
# Interactive section #
#######################

prompt_hawkbit_users() {
	local HAWKBIT_USER_ADMIN=admin user
	local HAWKBIT_USER_DEVICE="" HAWKBIT_USER_MKSWU=""
	local HAWKBIT_USER_MKSWU_ROLLOUT=""

	prompt_reply HAWKBIT_USER_ADMIN "Hawkbit admin user name"
	if hawkbit_add_user "$HAWKBIT_USER_ADMIN"; then
		# skip if admin user was already created
		while true; do
			read -r -p $"Extra admin user name (empty to stop): " user
			[[ -n "$user" ]] || break
			hawkbit_add_user "$user" || echo $"$user already exists!"
		done
	fi

	if prompt_yesno HAWKBIT_USER_DEVICE \
			$"Create hawkBit device user? (for autoregistration)"; then
		hawkbit_add_user "device"
	fi

	if prompt_yesno HAWKBIT_USER_MKSWU \
			$"Create hawkBit mkswu user? (for automated image upload)"; then
		hawkbit_add_user "mkswu"
	fi
}

prompt_reverse_proxy() {
	local CERT="$CONFIG_DIR/data/nginx_certs/proxy.crt"
	local PRIVKEY="$CONFIG_DIR/data/nginx_certs/proxy.key"
	local REVERSE_PROXY_CLIENT_CERT=""
	local REVERSE_PROXY_CLIENT_CERT_MANDATORY=""
	local REVERSE_PROXY_SELFCERT_SETUP_TEXT=""
	local REVERSE_PROXY_SELFCERT_SETUP_TEXT_DEFAULT=n
	local STOP_CONFLICT_SERVICE=""
	declare -a hawkbit_proxy_conf_fragments=( "*_base" "*_cert_domain" )


	if ! prompt_yesno REVERSE_PROXY "Setup TLS reverse proxy?"; then
		update_template "docker-compose.yml/20_hawkbit_ports" -e 's/#LISTEN//'
		return 0
	fi

	if systemctl is-active --quiet lighttpd; then
		NOSAVE=1 prompt_yesno STOP_CONFLICT_SERVICE $"Stop lighttpd service?" \
				$"lighttpd is running and conflicts with the reverse proxy setup." \
			|| error $"Please stop lighttpd manually"
		sudo systemctl stop lighttpd \
			|| error $"Could not stop lighttpd service"
		sudo systemctl disable lighttpd \
			|| error $"Could not disable lighttpd service"
	fi

	generate_cert
	update_template "docker-compose.yml/20_hawkbit_ports" -e 's/#EXPOSE//'
	update_template "hawkbit_proxy.conf/10_cert_domain" -e "s/CERT_DOMAIN/$REVERSE_PROXY_CERT_DOMAIN/"
	update_template "hawkbit_proxy.conf/25_cert_domain" -e "s/CERT_DOMAIN/$REVERSE_PROXY_CERT_DOMAIN/"
	update_template "hawkbit_application.properties/proxy" -e "s/CERT_DOMAIN/$REVERSE_PROXY_CERT_DOMAIN/"

	prompt_reply REVERSE_PROXY_CLIENT_CERT \
		$"CA file path (leave empty to disable client TLS authentication)" \
		$"If you would like to setup client certificate authenication a ca is required."
	if [[ -n "$REVERSE_PROXY_CLIENT_CERT" ]]; then
		[[ -e "$REVERSE_PROXY_CLIENT_CERT" ]] \
			|| error $"ca file $REVERSE_PROXY_CLIENT_CERT does not exist. Reset proxy settings with --reset-proxy"
		cp "$REVERSE_PROXY_CLIENT_CERT" "$CONFIG_DIR/data/nginx_certs/ca.crt"
		update_template "hawkbit_application.properties/auth_certif" \
				-e 's/=false/=true/'
		hawkbit_proxy_conf_fragments+=( "*_tlsauth*" )
		if prompt_yesno REVERSE_PROXY_CLIENT_CERT_MANDATORY \
				$"Also disallow token authentication?"; then
			update_template "hawkbit_proxy.conf/40_tlsauth_ca" \
				-e 's/optional/on/'
			update_template "hawkbit_application.properties/auth_token" \
				-e 's/=true/=false/'
		fi
	fi
	if prompt_yesno REVERSE_PROXY_LETSENCRYPT \
			$"Setup certbot container to obtain certificate?" \
			$"If the host is directly accessible over internet, it it possible to setup a let's" \
			$"encrypt certificate instead of the self-signed one. Accepting means you agree to the TOS:" \
			"https://letsencrypt.org/documents/LE-SA-v1.2-November-15-2017.pdf" \
	    && check_letsencrypt; then
		hawkbit_proxy_conf_fragments+=( "*_letsencrypt" )
	elif ! prompt_yesno REVERSE_PROXY_SELFCERT_SETUP_TEXT; then
		echo
		echo $"You need to copy $CERT to /usr/local/share/ca-certificates/ and run update-ca-certificates."
		echo $"The recommended way of doing this is including this base64-encoded copy of"
		echo $"the certificate into the example's hawkbit_register.sh script SSL_CA_BASE64:"
		echo
		base64 "$CERT"
		echo
		echo
		echo $"Should you want to use a let's encrypt certificate, you can run $SCRIPT_BASE again with --letsencrypt"
		REVERSE_PROXY_SELFCERT_SETUP_TEXT=y
		save_prompt REVERSE_PROXY_SELFCERT_SETUP_TEXT
	fi
	assemble_fragments data/nginx_conf/hawkbit_proxy.conf "${hawkbit_proxy_conf_fragments[@]}"
}

check_requirements() {
	local DO_INSTALL="" DO_STOP=""

	if ! command -v docker > /dev/null; then
		NOSAVE=1 prompt_yesno DO_INSTALL $"Docker is not installed. Install it?" \
			|| error $"Please check https://docs.docker.com/get-docker/ and install docker"
		sudo apt install docker.io \
			|| error $"Install failed, please check https://docs.docker.com/get-docker/ and install manually"
	fi
	if ! command -v docker-compose > /dev/null; then
		NOSAVE=1 prompt_yesno DO_INSTALL $"docker-compose is not installed. Install it?" \
			|| error $"Please install docker-compose"
		sudo apt install docker-compose \
			|| error $"Install failed, please install docker-compose manually"
	fi
	if ! command -v htpasswd > /dev/null; then
		NOSAVE=1 prompt_yesno DO_INSTALL $"htpasswd is required for password generation. Install it?" \
			|| error $"Please install htpasswd (apache2-utils)"
		sudo apt install apache2-utils \
			|| error $"Install failed, please install apache2-utils manually"
	fi
}


main() {
	local REVERSE_PROXY_CERT_DOMAIN=""
	local CONFIG_DIR=""
	local SUDO=""
	local REVERSE_PROXY="" REVERSE_PROXY_DEFAULT=n
	local REVERSE_PROXY_LETSENCRYPT="" REVERSE_PROXY_LETSENCRYPT_DEFAULT="n"
	local DOCKER_NEEDS_SUDO=""
	local NODEFAULT="" NOSAVE=""
	local RUN_COMPOSE=""
	local reset_proxy="" reset_users="" add_users=() del_users=() user

	local arg argopt
	while [[ "$#" -gt 0 ]]; do
		local arg="$1" argopt="y"
		# split --foo=bar first
		case "$arg" in
		"--"*=*)
			argopt="${arg#*=}"
			arg="${arg%%=*}"
			;;
		esac
		case "$arg" in
		"--dir")
			[[ "$#" -ge 2 ]] || error $"$arg requires an argument"
			CONFIG_DIR="$(realpath "$2")";
			shift
			;;
		"--domain")
			[[ "$#" -ge 2 ]] || error $"$arg requires an argument"
			REVERSE_PROXY_CERT_DOMAIN=$2;
			save_prompt REVERSE_PROXY_CERT_DOMAIN
			shift
			;;
		"--letsencrypt")
			REVERSE_PROXY_LETSENCRYPT=$argopt
			save_prompt REVERSE_PROXY_LETSENCRYPT
			;;
		"--reset-proxy")
			reset_proxy=1
			;;
		"--reset-users")
			reset_users=1
			;;
		"--add-user")
			[[ "$#" -ge 2 ]] || error $"$arg requires an argument"
			add_users+=( "$2" )
			shift
			;;
		"--del-user")
			[[ "$#" -ge 2 ]] || error $"$arg requires an argument"
			del_users+=( "$2" )
			shift
			;;
		"--help"|"-h")
			usage
			exit 0
			;;
		*)
			error $"Unhandled arguments: $@"
		esac
		shift
	done

	check_requirements

	if [[ -z "$CONFIG_DIR" ]]; then
		# If not explicitely configured try possible locations for
		# already existing dir
		for CONFIG_DIR in "$(dirname "$0")" "$PWD" \
				  "$PWD/hawkbit-compose" "$HOME/hawkbit-compose"; do
			[[ -e "$CONFIG_DIR/setup_container.conf" ]] && break
		done
		# Also try SUDO_USER's home if set
		if ! [[ -e "$CONFIG_DIR/setup_container" ]] && [[ -n "$SUDO_USER" ]]; then
			CONFIG_DIR="$(getent passwd "$SUDO_USER" | cut -d: -f6)"
			# ... but only if what we found made sense
			if [[ -d "$CONFIG_DIR" ]]; then
				CONFIG_DIR="$CONFIG_DIR/hawkbit-compose"
			else
				CONFIG_DIR="$HOME/hawkbit-compose"
			fi
		fi
		# if not already configured confirm location with user
		if ! [[ -e "$CONFIG_DIR/setup_container.conf" ]]; then
			NOSAVE=1 prompt_reply CONFIG_DIR \
				$"Where should we store docker-compose configuration and hawkBit data?"
		fi
	fi

	CONFIG_DIR=$(realpath -m "$CONFIG_DIR")
	local FRAGMENTS_SRC="$SCRIPT_DIR/fragments"
	local FRAGMENTS="$CONFIG_DIR/data/fragments"
	local SETUP_CONF="$CONFIG_DIR/setup.conf"
	local PROMPT_FILE="$CONFIG_DIR/setup_container.conf"

	if ! [[ -d "$CONFIG_DIR" ]]; then
		mkdir -p "$CONFIG_DIR" \
			|| error $"Could not create directory"
		touch "$PROMPT_FILE"
	fi
	if [[ -e "$CONFIG_DIR/setup_container.conf" ]]; then
		if [[ "$(stat -L -c %d:%i "$CONFIG_DIR/$SCRIPT_BASE" 2>/dev/null)" != "$(stat -L -c %d:%i "$0")" ]]; then
			echo $"Creating link to $SCRIPT_BASE in $CONFIG_DIR"
			rm -f "$CONFIG_DIR/$SCRIPT_BASE"
			ln -s "$SCRIPT_DIR/$SCRIPT_BASE" "$CONFIG_DIR"/ \
				|| error $"Could not create script link"
		fi
	fi
	cd "$CONFIG_DIR" \
		|| error $"Could not enter config dir"
	[[ "${SETUP_CONF#/}" = "$SETUP_CONF" ]] \
		&& SETUP_CONF="./$SETUP_CONF"
	[[ -e "$SETUP_CONF" ]] && . "$SETUP_CONF"

	[[ -d "$CONFIG_DIR/data" ]] || mkdir "$CONFIG_DIR/data" \
		|| error $"Could not create directory"
	[[ -d "$FRAGMENTS" ]] || mkdir "$FRAGMENTS" \
		|| error $"Could not create directory"


	prompt_reply DOCKER_NEEDS_SUDO
	case "$DOCKER_NEEDS_SUDO" in
	no) ;;
	yes) SUDO=sudo;;
	*)
		DOCKER_NEEDS_SUDO=no
		if ! docker ps >/dev/null 2>&1; then
			[[ "$(id -u)" = 0 ]] && error $"Could not use docker, is the service running?"
			SUDO=sudo
			echo $"Could not connect to docker daemon, trying with sudo... "
			$SUDO docker ps >/dev/null 2>&1 \
				|| error $"Could not use docker, is the service running?"
			echo $"ok!"
			DOCKER_NEEDS_SUDO=yes
		fi
		save_prompt DOCKER_NEEDS_SUDO
		;;
	esac

	if [[ -e "$CONFIG_DIR/docker-compose.yml" ]] \
		&& echo $"Checking if container is running... ${SUDO:+(this requires sudo)}" \
		&& [[ -n "$($SUDO docker-compose -f "$CONFIG_DIR/docker-compose.yml" ps -q 2>/dev/null)" ]] \
		&& NOSAVE=1 prompt_yesno RUN_COMPOSE $"Stop hawkBit containers?" \
			$"hawkBit containers seem to be running, updating config files" \
			$"might not work as expected."; then
		$SUDO docker-compose -f "$CONFIG_DIR/docker-compose.yml" down \
			|| error $"Could not stop containers"
	fi

	[[ -n "$reset_proxy" ]] && reverse_proxy_reset
	[[ -n "$reset_users" ]] && hawkbit_reset_users
	for user in "${add_users[@]}"; do
		RESET_PW=1 hawkbit_add_user "$user"
	done
	if [[ "${#del_users[@]}" -gt 0 ]]; then
		hawkbit_del_user "${del_users[@]}"
	fi
	prompt_hawkbit_users
	prompt_reverse_proxy
	finalize_hawkbit
	finalize_compose
	# requires compose files so run last
	finalize_letsencrypt

	echo
	echo $"Setup finished! Use docker-compose now to manage the containers"
	echo $"or run $CONFIG_DIR/$SCRIPT_BASE again to change configuration."

	RUN_COMPOSE=""
	if NOSAVE=1 prompt_yesno RUN_COMPOSE $"Start hawkBit containers?"; then
		$SUDO docker-compose up -d
	fi
}

main "$@"
