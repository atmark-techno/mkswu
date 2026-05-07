# mkswu scripts

mkswu scripts are both "embedded" in SWU and also installed on armadillo ("vendored" in /usr/libexec/mkswu/).
The most recent version runs (scripts in SWU run if version is equal).

The versions are displayed when running swupdate with -v, but correspond to:
- version shown in SWU with mkswu --show (sw-description version field)
- /usr/libexec/mkswu/version for installed scripts

## Scripts execution flow

Scripts run in the following order:
* `scripts_pre.sh`
** self-extracts all the srcipts in $TMPDIR/scripts-mkswu
** `pre_init`: checks versions in SWU / check SWU is installeable
Update only really starts after this, `scripts-mkswu/update_started` and other files
described below are created and initial cleanup occurs on start.
** `pre_boot`: create `/dev/swupdate_bootdev` if boot is to be installed or copies bootloader if needed
** `pre_rootfs`: copy rootfs to target if needed and mounts it
** `pre_appfs`: snapshot container images and volumes before update starts
* SWU content in the order of files within the SWU
(in general, the order of `swdesc_*` commands in the desc files)
* `scripts/post.sh`
** `post_init`: grabs variables left by `pre_init`
** `post_appfs`: exchange container partitions if required
** `post_rootfs`: finish up rootfs (e.g. uboot env config, fstab)
** `post_boot`: finish switching bootloader (mmc bootpart)
** `post_success`: notifies success, logs update etc
** either poweroffs, exit (wait), restarts containers (container), or reboot
* `scripts/cleanup.sh` is only run if there was an error, after whichever step failed
(possibly post.sh)

## Script data for debug

`scripts-mkswu` directory should contain:
- `update_started` marker if updated started
- `rootdev` with e.g. `/dev/mmcblk2`
- `ab` with 0 (installs to `${rootdev}p1`) or 1 (installs to `${rootdev}p2`)
- `needs_reboot` file if rebooting at end of update
- `update_rootfs` if rootfs is RW
- `versions.old`: versions as of before this SWU
- `versions.init`: versions as of before all SWUs (for chained update, or same as above)
- `versions.present`: versions included in SWU
- `versions.merged`: versions as it will be after install (old + present)

Note the directory is removed after the SWU is done, except for chained/installer updates which remove only the `update_started` marker

## Special cases

### Scripts order when running vendored scripts

When running scripts from armadillo, the execution order is as follow:
* `/usr/libexec/mkswu/pre.sh`
* `scripts_pre.sh` in SWU: extracts data to scripts-mkswu, but do not remove data left behind from vendored pre,
and stops immediately (swupdate wrote `DEBUG_SKIP_SCRIPTS` in sw-description)
* `scripts/post.sh` from SWU: skipped to `DEBUG_SKIP_SCRIPTS`
* `/usr/libexec/mkswu/post.sh` (or cleanup.sh on failure)

### SWUs installed in installer

Installer takes care of setting up /target, so `pre_init` does bare minimum (updating versions) and exits immediately.
`post_init` checks /target/etc/shadow for empty passwords and updates /target/etc/swupdate.pem, /target/etc/sw-versions and exits.

### Chained SWUs

`swupdate-chain` in abos-base sets some variables for us:
- `SWUPDATE_CHAIN_ID` should be constant for the whole chain, if this changes install fails
- `SWUPDATE_CHAIN_IDX`, `SWUPDATE_CHAIN_COUNT`: number of current SWU and count of expected SWUs (for logs, and to determine if the SWU is last in chain)
- `SWUPDATE_CHAIN_STARTED`: set after any SWU was installed, to decide if install should terminate when last SWU has nothing to do.

mkswu scripts responsibility:
- run mkswu pre script only once, on first SWU that actually starts something
- run mkswu cleanup on error (no more SWU will be installed after any error in chain)
- run mkswu post script on last SWU, either at the end if it is installed or in its pre script if skipping (nothing to do)

swupdate-chain responsibility:
- properly set variables and detect update started and errors (with `mkswu_status` file)
- run mkswu post script after last SWU if skipped due to not found/bad sig (e.g. pre script was not run)

