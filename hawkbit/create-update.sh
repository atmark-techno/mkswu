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

	module=$(jq -r '.[].id' < softwaremodule)
	[ "$module" = "null" ] && error_f softwaremodule "software module has no 'id'?"

	curl_check -X POST -H "Content-Type: multipart/form-data" \
		"$HAWKBIT_URL/rest/v1/softwaremodules/$module/artifacts" \
		-F "file=@$file" -o upload_artifact \
		|| error_f upload_artifact "Could not upload artifact for software module:"

# {"createdBy":"mkimage","createdAt":1637562874217,"lastModifiedBy":"mkimage","lastModifiedAt":1637562874217,"hashes":{"sha1":"a5c7bbff56b80194985c95bceba28b6f60ec71c9","md5":"0a942829648ccf6aa42387b592f330dd","sha256":"a2db3163c981b4bdbf6f340841266e3c17e88c4a0e8273b503342d2354aee6be"},"providedFilename":"embed_container_nginx.swu","size":8002048,"_links":{"self":{"href":"http://10.1.1.1:8080/rest/v1/softwaremodules/11/artifacts/18"},"download":{"href":"http://10.1.1.1:8080/rest/v1/softwaremodules/11/artifacts/18/download"}},"id":18}


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

	dist=$(jq -r '.[].id' < distributionset)
	[ "$dist" = "null" ] && error_f distributionset "distribution set has no 'id'?"

	curl_check -X POST -H "Content-Type: application/json" \
		"$HAWKBIT_URL/rest/v1/distributionsets/$dist/assignedSM" \
		-o assign_sm -d '[{"id": "'"$module"'"}]' \
		|| error_f assign_sm "Could not assign software module to distribution:"
# empty on success
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

	tmpdir=$(mktemp -d -t hawkbit_update.XXXXXX) \
		|| error "Could not create tmpdir"
	trap "rm -rf '$tmpdir'" EXIT

	# XXX parse opts
	local file="$(realpath "$1")"
	local name="nginx test"
	local version="3"
	local description
	local swutype="application"

	cd "$tmpdir" || error "Could not enter $tmpdir"
	[ -e "$file" ] || error "file $file does not exist?"

	# get default values from sw-description:
	# - description = description if set
	# - name = name of first component found
	# - version = version of first component found
	# - swutype = application unless base_os is set
	cpio -i sw-description < "$file" || error "$file is not a swu image?"
	name=$(awk '$1 == "name" { print; exit; }' < sw-description | cut -d\" -f2)
	version=$(awk '$1 == "name" { OK=1; }
			OK && $1 == "version" { print; exit; }' < sw-description | cut -d\" -f2)
	description=$(awk '$1 == "description" { print; exit; }' < sw-description | cut -d\" -f2)
	swutype="application"
	grep -qE 'name.*"base_os"' sw-description && swutype="os"

	create_update
	create_rollout
	echo "Created rollout for $name $version successfully"
}

main "$@"
