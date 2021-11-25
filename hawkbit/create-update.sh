#!/bin/sh

HAWKBIT_USER=mkimage
HAWKBIT_PASSWORD=
HAWKBIT_URL=
VENDOR=atmark
# comma-separated list of devices 'id'
ROLLOUT_TEST_DEVICES=
ROLLOUT_N_GROUPS=2
ROLLOUT_SUCCESS_THRESHOLD=70
ROLLOUT_ERROR_THRESHOLD=30

error() {
	printf "%s\n" "$@" >&2
	exit 1
}

error_f() {
	local f="$1"
	shift
	printf "%s\n" "$@" >&2
	jq '.' < "$f" >&2
	exit 1
}

curl_check() {
	local httpcode

	# curl --fail does not keep the body and error and we want it for error message
	# curl --fail-with-body requires curl 7.76+: emulate it...
	# from https://superuser.com/a/1641410

	if ! httpcode=$(curl -s -u "$HAWKBIT_USER:$HAWKBIT_PASSWORD" \
				--write-out "%{http_code}" "$@"); then
		# run again without -s for error
		echo "curl failed:" >&2
		curl -u "$HAWKBIT_USER:$HAWKBIT_PASSWORD" "$@"
		exit 1
	fi
			
	[ "$(( httpcode >= 200 && httpcode < 300 ))" = 1 ]
}




dist_types() {
	case "$1" in
	application) echo app;;
	os) echo os;;
	*) error "invalid type $1: expected application or os";;
	esac
}

create_update() {
	curl_check -X GET -H "Accept: application/hal+json" \
			-o modules "$HAWKBIT_URL/rest/v1/softwaremodules" \
		|| error_f modules "Could not list modules"
# {"content":[{"createdBy":"mkimage","createdAt":1637727156396,"lastModifiedBy":"mkimage","lastModifiedAt":1637727158363,"name":"container_nginx","description":"コンテナの更新","version":"1","type":"application","vendor":"atmark","deleted":false,"_links":{"self":{"href":"http://10.1.1.1:8080/rest/v1/softwaremodules/1"}},"id":1},{"createdBy":"mkimage","createdAt":1637727396644,"lastModifiedBy":"mkimage","lastModifiedAt":1637727396730,"name":"container_nginx","description":"コンテナの更新","version":"2","type":"application","vendor":"atmark","deleted":false,"_links":{"self":{"href":"http://10.1.1.1:8080/rest/v1/softwaremodules/2"}},"id":2},{"createdBy":"mkimage","createdAt":1637798358687,"lastModifiedBy":"admin","lastModifiedAt":1637798523798,"name":"testme","description":"テスト","version":"2.2.0.010","type":"application","vendor":"atmark","deleted":false,"_links":{"self":{"href":"http://10.1.1.1:8080/rest/v1/softwaremodules/3"}},"id":3}],"total":3,"size":3}
	module=$(jq '.content | map(select(.name == "'"$name"'"
			and .version == "'"$version"'")) | .[0].id' < modules)
	if [ "$module" = null ]; then
		curl_check -X POST -H "Content-Type: application/json" \
			"$HAWKBIT_URL/rest/v1/softwaremodules" \
			-o softwaremodule -d '[{
				"vendor": "'"$VENDOR"'",
				"name": "'"$name"'",
				"version": "'"$version"'",
				"description": "'"$description"'",
				"type": "'"$swutype"'"
			}]' || error_f softwaremodule "could not create software module:"
# [{"createdBy":"mkimage","createdAt":1637561017365,"lastModifiedBy":"mkimage","lastModifiedAt":1637561017365,"name":"nginx test","description":"nginx image","version":"1","type":"application","vendor":"atmark","deleted":false,"_links":{"self":{"href":"http://10.1.1.1:8080/rest/v1/softwaremodules/11"}},"id":11}]

		module=$(jq -r '.[0].id' < softwaremodule)
		[ "$module" = "null" ] && error_f softwaremodule "software module has no 'id'?"
	fi

	curl_check -X GET -H "Accept: application/hal+json" \
			-o artifacts "$HAWKBIT_URL/rest/v1/softwaremodules/$module/artifacts" \
		|| error_f artifacts "could not get artifacts from module we just created?"
# [{"createdBy":"mkimage","createdAt":1637727396730,"lastModifiedBy":"mkimage","lastModifiedAt":1637727396730,"hashes":{"sha1":"50d44854a3a7c8f87f5b0d274a69dda5ca0ab728","md5":"5a33b84a26a8f30b5dbabc9045f66014","sha256":"d4fbf1061193e63abca0c9daf2aa8dbefdd856542c6cc9ec18412be3b22ca585"},"providedFilename":"container.swu","size":20992,"_links":{"self":{"href":"http://10.1.1.1:8080/rest/v1/softwaremodules/2/artifacts/2"}},"id":2}]
	if [ "$(cat artifacts)" != "[]" ]; then
		local local_csum hawkbit_csum

		hawkbit_csum=$(jq -r '.[].hashes.sha256' < artifacts)
		local_csum=$(sha256sum "$file") \
			|| error "Could not read $file"
		local_csum=${local_csum%% *}
		[ "$local_csum" = "$hawkbit_csum" ] \
			|| error_f artifacts "Software $name $version already exists with artifacts different from $file"
	else
		curl_check -X POST -H "Content-Type: multipart/form-data" \
			"$HAWKBIT_URL/rest/v1/softwaremodules/$module/artifacts" \
			-F "file=@$file" -o upload_artifact \
			|| error_f upload_artifact "Could not upload artifact for software module:"
# {"createdBy":"mkimage","createdAt":1637562874217,"lastModifiedBy":"mkimage","lastModifiedAt":1637562874217,"hashes":{"sha1":"a5c7bbff56b80194985c95bceba28b6f60ec71c9","md5":"0a942829648ccf6aa42387b592f330dd","sha256":"a2db3163c981b4bdbf6f340841266e3c17e88c4a0e8273b503342d2354aee6be"},"providedFilename":"embed_container_nginx.swu","size":8002048,"_links":{"self":{"href":"http://10.1.1.1:8080/rest/v1/softwaremodules/11/artifacts/18"},"download":{"href":"http://10.1.1.1:8080/rest/v1/softwaremodules/11/artifacts/18/download"}},"id":18}
	fi

	curl_check -X GET -H "Accept: application/hal+json" \
			-o distributionsets "$HAWKBIT_URL/rest/v1/distributionsets" \
		|| error "Could not list distribution sets"
# {"content":[{"createdBy":"mkimage","createdAt":1637727158497,"lastModifiedBy":"mkimage","lastModifiedAt":1637727158637,"name":"container_nginx","description":"コンテナの更新","version":"1","modules":[{"createdBy":"mkimage","createdAt":1637727156396,"lastModifiedBy":"mkimage","lastModifiedAt":1637727158363,"name":"container_nginx","description":"コンテナの更新","version":"1","type":"application","vendor":"atmark","deleted":false,"_links":{"self":{"href":"http://10.1.1.1:8080/rest/v1/softwaremodules/1"}},"id":1}],"requiredMigrationStep":false,"type":"app","complete":true,"deleted":false,"_links":{"self":{"href":"http://10.1.1.1:8080/rest/v1/distributionsets/1"}},"id":1},{"createdBy":"mkimage","createdAt":1637727396780,"lastModifiedBy":"mkimage","lastModifiedAt":1637727396863,"name":"container_nginx","description":"コンテナの更新","version":"2","modules":[{"createdBy":"mkimage","createdAt":1637727396644,"lastModifiedBy":"mkimage","lastModifiedAt":1637727396730,"name":"container_nginx","description":"コンテナの更新","version":"2","type":"application","vendor":"atmark","deleted":false,"_links":{"self":{"href":"http://10.1.1.1:8080/rest/v1/softwaremodules/2"}},"id":2}],"requiredMigrationStep":false,"type":"app","complete":true,"deleted":false,"_links":{"self":{"href":"http://10.1.1.1:8080/rest/v1/distributionsets/2"}},"id":2},{"createdBy":"mkimage","createdAt":1637798427289,"lastModifiedBy":"mkimage","lastModifiedAt":1637798427362,"name":"testme","description":"テスト","version":"2.2.0.010","modules":[{"createdBy":"mkimage","createdAt":1637798358687,"lastModifiedBy":"admin","lastModifiedAt":1637798523798,"name":"testme","description":"テスト","version":"2.2.0.010","type":"application","vendor":"atmark","deleted":false,"_links":{"self":{"href":"http://10.1.1.1:8080/rest/v1/softwaremodules/3"}},"id":3}],"requiredMigrationStep":false,"type":"app","complete":true,"deleted":false,"_links":{"self":{"href":"http://10.1.1.1:8080/rest/v1/distributionsets/3"}},"id":3}],"total":3,"size":3}
	dist=$(jq '.content | map(select(.name == "'"$name"'"
			and .version == "'"$version"'")) | .[0].id' < distributionsets)
	if [ "$dist" = null ]; then
		curl_check -X POST -H "Content-Type: application/json" \
			"$HAWKBIT_URL/rest/v1/distributionsets" \
			-o distributionset -d '[{
				"requiredMigrationStep": false,
				"name": "'"$name"'",
				"version": "'"$version"'",
				"description": "'"$description"'",
				"type": "'"$(dist_types "$swutype")"'"
			}]' || error_f distributionset "Could not create distribution set:"
# [{"createdBy":"mkimage","createdAt":1637563046037,"lastModifiedBy":"mkimage","lastModifiedAt":1637563046037,"name":"nginx test","description":"nginx image","version":"1","modules":[],"requiredMigrationStep":false,"type":"app","complete":false,"deleted":false,"_links":{"self":{"href":"http://10.1.1.1:8080/rest/v1/distributionsets/10"}},"id":10}]

		dist=$(jq -r '.[0].id' < distributionset)
		[ "$dist" = "null" ] && error_f distributionset "distribution set has no 'id'?"
	fi

	curl_check -X GET -H "Accept: application/hal+json" \
			-o assigned_sm_check "$HAWKBIT_URL/rest/v1/distributionsets/$dist/assignedSM" \
		|| error_f assigned_sm_check "Could not query assigned SM of distribution set we just created?"
# {"content":[{"createdBy":"mkimage","createdAt":1637727156396,"lastModifiedBy":"mkimage","lastModifiedAt":1637727158363,"name":"container_nginx","description":"コンテナの更新","version":"1","type":"application","vendor":"atmark","deleted":false,"_links":{"self":{"href":"http://10.1.1.1:8080/rest/v1/softwaremodules/1"}},"id":1}],"total":1,"size":1}
	local assignedSM=$(jq '.content | .[].id' < assigned_sm_check)
	if [ -z "$assignedSM" ]; then
		curl_check -X POST -H "Content-Type: application/json" \
			"$HAWKBIT_URL/rest/v1/distributionsets/$dist/assignedSM" \
			-o assign_sm -d '[{"id": "'"$module"'"}]' \
			|| error_f assign_sm "Could not assign software module to distribution:"
# empty on success
	elif [ "$assignedSM" != "$module" ]; then
		error "dist $name $version already exists with assignedSM $assignedSM != $module"
	fi
}

create_rollout() {
	local groups
	if [ -n "$ROLLOUT_TEST_DEVICES" ]; then
		groups='{
				"name": "test devices",
				"description": "test devices",
				"targetFilterQuery": "id =IN= ('"$ROLLOUT_TEST_DEVICES"')",
				"successCondition": {
					"condition": "THRESHOLD",
					"expression": "100"
				},
				"successAction": {
					"expression": "",
					"action": "NEXTGROUP"
				},
				"errorCondition": {
					"condition": "THRESHOLD",
					"expression": "1"
				},
				"errorAction": {
					"expression": "",
					"action": "PAUSE"
				}
			}'
	fi
	local i=0 percent=$((100/$ROLLOUT_N_GROUPS))
	while [ "$i" -lt "$ROLLOUT_N_GROUPS" ]; do
		[ "$((i+1))" -eq "$ROLLOUT_N_GROUPS" ] && percent=100
		groups="${groups:+$groups,}
			"'{
				"name": "bulk'"$i"'",
				"description": "normal devices",
				"targetFilterQuery": "",
				"targetPercentage": "'"$percent"'",
				"successCondition": {
					"condition": "THRESHOLD",
					"expression": "'"$ROLLOUT_SUCCESS_THRESHOLD"'"
				},
				"successAction": {
					"expression": "",
					"action": "NEXTGROUP"
				},
				"errorCondition": {
					"condition": "THRESHOLD",
					"expression": "'"$ROLLOUT_ERROR_THRESHOLD"'"
				},
				"errorAction": {
					"expression": "",
					"action": "PAUSE"
				}
			}'
		i=$((i+1))
	done
	curl_check -X POST -H 'Content-Type: application/json' \
		"$HAWKBIT_URL/rest/v1/rollouts" \
		-o rollout -d '{
			"name": "'"$name $version"'",
			"description": "'"$description"'",
			"distributionSetId": '"$dist"',
			"targetFilterQuery": "id == *",
			"groups": [
				'"$groups"'
			]
		}' || error_f rollout "Could not create rollout:"
# {"createdBy":"admin","createdAt":1637558593530,"lastModifiedBy":"admin","lastModifiedAt":1637558593530,"name":"nginx 2","description":"rollout nginx 2","targetFilterQuery":"id == *","distributionSetId":9,"status":"creating","totalTargets":11,"totalTargetsPerStatus":{"running":0,"notstarted":11,"scheduled":0,"cancelled":0,"finished":0,"error":0},"deleted":false,"type":"forced","_links":{"start":{"href":"http://10.1.1.1:8080/rest/v1/rollouts/14/start"},"pause":{"href":"http://10.1.1.1:8080/rest/v1/rollouts/14/pause"},"resume":{"href":"http://10.1.1.1:8080/rest/v1/rollouts/14/resume"},"approve":{"href":"http://10.1.1.1:8080/rest/v1/rollouts/14/approve{?remark}","templated":true},"deny":{"href":"http://10.1.1.1:8080/rest/v1/rollouts/14/deny{?remark}","templated":true},"groups":{"href":"http://10.1.1.1:8080/rest/v1/rollouts/14/deploygroups?offset=0&limit=50{&sort,q}","templated":true},"self":{"href":"http://10.1.1.1:8080/rest/v1/rollouts/14"}},"id":14}

}

main() {
	local tmpdir
	local module dist

	command -v curl > /dev/null || error "Need curl installed"
	command -v jq > /dev/null || error "Need jq installed"

	tmpdir=$(mktemp -d -t hawkbit_update.XXXXXX) \
		|| error "Could not create tmpdir"
	trap "rm -rf '$tmpdir'" EXIT

	# XXX parse opts?
	# e.g. add rollout creation or not
	local file="$(realpath "$1")"
	local name="" version="" description=""
	local swutype="application"

	cd "$tmpdir" || error "Could not enter $tmpdir"
	[ -e "$file" ] || error "file $file does not exist?"

	# get default values from sw-description:
	# - description = description if set
	# - name = name of first component found
	# - version = version of first component found
	# - swutype = application unless base_os is set
	cpio -i sw-description < "$file" || error "$file is not a swu image?"
	if grep -q MAIN_VERSION sw-description; then
		name=$(sed -ne 's/.*MAIN_COMPONENT //p' sw-description)
		version=$(sed -ne 's/.*MAIN_VERSION //p' sw-description)
	else
		name=$(sed -ne '/^ *name =/ { s/.*"\(.*\)".*/\1/p; q }' < sw-description)
		version=$(sed -ne '/^ *name =/ { N; s/.*version = "\(.*\)".*/\1/p; q }' < sw-description)
	fi
	description=$(sed -ne '/^ *description =/ { s/.*"\(.*\)".*/\1/p; q }' < sw-description)
	swutype="application"
	grep -qE 'name.*"base_os"' sw-description && swutype="os"
	[ -n "$name" ] && [ -n "$version" ] || error "could not guess image name/version"

	create_update
	create_rollout
	echo "Created rollout for $name $version successfully"
}

main "$@"
