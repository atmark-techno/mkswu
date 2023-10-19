---
title: List of common errors
---

swupdate messages can be found in `/var/log/messages` regardless of the way it is started, if an image is not installed after you think it should have been please check for 'swupdate' messages in this file.

When an error happens, multiple error messages are usually printed. In the table below we always reference the first error message being printed, if there is a message enclosed in dash lines and starting with `/!\` this is the one you want.
For example, in the short log below, the message to look up in this table is `ERROR : /!\ Nothing to do -- failing on purpose to save bandwidth`
```
[INFO ] : SWUPDATE running :  [main] : Running on AGX4500 Revision at1
[INFO ] : SWUPDATE started :  Software Update started !
[ERROR] : SWUPDATE failed [0] ERROR : ----------------------------------------------
[ERROR] : SWUPDATE failed [0] ERROR : /!\ Nothing to do -- failing on purpose to save bandwidth
[ERROR] : SWUPDATE failed [0] ERROR : ----------------------------------------------
[ERROR] : SWUPDATE failed [0] ERROR : Command failed: sh -c 'sh $1 ' -- /var/tmp//scripts_pre.sh.zst.enc
[ERROR] : SWUPDATE failed [0] ERROR : Error streaming scripts_pre.sh.zst.enc
[ERROR] : SWUPDATE failed [1] Image invalid or corrupted. Not installing ...
[INFO ] : No SWUPDATE running :  Waiting for requests...
```

## Index {#index}

Each item below contains an example of the full log message and an explanation of why it failed and how to fix it.

* [Nothing to do](#nothing_to_do)
  * `ERROR : /!\ Nothing to do -- failing on purpose to save bandwidth`
* [Signature verification failed](#sign_fail)
  * `ERROR : Signature verification failed`
* [ZSTD\_decompressStream failed](#bad_enc)
  * `ERROR : ZSTD_decompressStream failed: Unknown frame descriptor`
* [no key provided for decryption](#no_encryption_key)
  * `ERROR : no key provided for decryption!`
* [No space left on device](#filesystem_full)
  * `ERROR : archive_write_data_block(): Write failed for '<file>': No space left on device`
  * `ERROR : cannot write 16384 bytes: No space left on device`
* [Cleanup of old images failed](#images_cleanup)
  * `ERROR : /!\ cleanup of old images failed: mismatching configuration/container update?`
* [Could not load/pull container](#bad_container)
  * `ERROR : /!\ Could not load /var/tmp//.....`
  * `ERROR : /!\ Could not pull ....`
* [Hardware is not compatible](#hw_compat_not_found)
  * `ERROR : HW compatibility not found`
* [Container image immediately removed](#image_removed)
  * `WARNING: Container image docker.io/library/nginx:alpine was added in swu but immediately removed`
* [Swupdate stuck](#stuck)
  * (swupdate never finishes)
* [No auto-install](#no_autoinstall)
  * (No message in `/var/log/messages` despite plugging in USB drive)
* [Anything else](#anything_else)
  * Anything else


## Nothing to do [↑](#index) {#nothing_to_do}

### Full log messages

```
armadillo:~# grep swupdate /var/log/messages
Apr  4 11:20:47 armadillo user.info swupdate: START Software Update started !
Apr  4 11:20:47 armadillo user.err swupdate: FAILURE ERROR : ----------------------------------------------
Apr  4 11:20:47 armadillo user.err swupdate: FAILURE ERROR : /!\ Nothing to do -- failing on purpose to save bandwidth
Apr  4 11:20:47 armadillo user.err swupdate: FAILURE ERROR : ----------------------------------------------
Apr  4 11:20:47 armadillo user.err swupdate: FAILURE ERROR : Command failed: sh -c 'sh $1 ' -- /var/tmp//scripts_pre.sh.zst.enc
Apr  4 11:20:47 armadillo user.err swupdate: FAILURE ERROR : Error streaming scripts_pre.sh.zst.enc
Apr  4 11:20:47 armadillo user.err swupdate: FATAL_FAILURE Image invalid or corrupted. Not installing ...
Apr  4 11:20:47 armadillo user.info swupdate: IDLE Waiting for requests...
```

### Cause of error

This message means that the SWU image that is being installed does not contain any new update.

SWU images include their own versions (as can be checked with `mkswu --show <image.swu>`), and a given version can only be installed once.

### How to fix

There are two ways of addressing this issue:

* Increase the versions you would like installed in the .desc file and regenerate the SWU image.  
If using `--version <component> <version>` the version part should be incremented.  
If using `swdesc_option version=...` this can be automated with `mkswu --update-version <file.desc>`

* Modify the local `/etc/sw-versions` file on armadillo to remove or downgrade the version you would like to reinstall. This is not recommended.

## Signature verification failed [↑](#index) {#sign_fail}

### Full log messages

````
armadillo:~# grep swupdate /var/log/messages
Apr  4 11:25:24 armadillo user.info swupdate: START Software Update started !
Apr  4 11:25:24 armadillo user.err swupdate: FAILURE ERROR : Signature verification failed
Apr  4 11:25:24 armadillo user.err swupdate: FAILURE ERROR : Compatible SW not found
Apr  4 11:25:24 armadillo user.err swupdate: FATAL_FAILURE Image invalid or corrupted. Not installing ...
Apr  4 11:25:24 armadillo user.info swupdate: IDLE Waiting for requests...
````

### Cause of error

SWU images are signed cryptographically at generation time, but the certificate used to sign the image is not present on the device.

The certificate/key pair used to sign your images are usually in `~/mkswu/swupdate.{pem,key}` on your computer, while the certificates allowed to be installed are listed in `/etc/swupdate.pem`.  
Your certificate is installed on the device when you install the `initial_setup` SWU, so it is also possible that the initial setup has just not been installed yet.

A variant of this error is when installing a container with `swdesc_usb_container`: the container image is verified separately from the SWU itself, so it is possible that the container.tar.sig file either does not match the container.tar content or was signed with a wrong key. Verifying files have been copied correctly should fix this.

Note that trying to install the initial setup SWU again after it has already been installed once will also generate this error, because it is signed with a different certificate/key pair which has been removed after the install.  
If you need to reinstall the initial setup please see [Reinstall another `initial_setup.swu`](#reinstall_initial_setup)

### How to fix

First, confirm the content of both the certificates on the device and on the machine mkswu is run on.

Certificates have been cut short with `...` below for brevity.  
Note that depending on the mkswu version used to generate your keys, you might not have the comments, but you should compare the content regardless of comments.

On the device:
```
armadillo:~# cat /etc/swupdate.pem
# atmark-1
-----BEGIN CERTIFICATE-----
MIIBuzCCAWCgAwIBAgIUbbibr2AEmw3ohnmkXeGPPf0glgcwCgYIKoZIzj0EAwIw

Either fix the existing containers `set_image` configuration if it was wrong, or if the image is not meant to be started automatically add a new config file with just `set_image <newimage>` and `set_autostart no` to disable autostart....
Ym7VNTvJTNMU82ZTiXk8
-----END CERTIFICATE-----
# atmark-2
-----BEGIN CERTIFICATE-----
MIIBvzCCAWagAwIBAgIUfagaF9RAjO2+x54PMqIlZkain9MwCgYIKoZIzj0EAwIw
...
LAzCERFEjT1UH1NutbSZr5IFdQ==
-----END CERTIFICATE-----
# swupdate.pem: my common name
-----BEGIN CERTIFICATE-----
MIIBmjCCAUCgAwIBAgIUFdtuYdCX1QwMNdhj+7QD+AF/o3AwCgYIKoZIzj0EAwIw
...
or0V6H5NZjclceCmWjdX+m/lSma7OUA5AuUdFU1f
-----END CERTIFICATE-----
```

On your PC:
```
[ATDE9 ~]$ cat ~/mkswu/swupdate.pem
# swupdate.pem: my common name
-----BEGIN CERTIFICATE-----
MIIBmjCCAUCgAwIBAgIUFdtuYdCX1QwMNdhj+7QD+AF/o3AwCgYIKoZIzj0EAwIw
...
or0V6H5NZjclceCmWjdX+m/lSma7OUA5AuUdFU1f
-----END CERTIFICATE-----
```

#### If the first key was the one time public certificate

If `/etc/swupdate.pem` on the device contains this certificate, as can be verified
by the `abos-ctrl status` command printing the following warning (also displayed on login):
```
WARNING: swupdate onetime public certificate is present, anyone can access this device
WARNING: Please install initial_setup.swu (from mkswu --init),
WARNING: or remove the first certificate from /etc/swupdate.pem
```

Then you have not installed the `initial_setup.swu` image yet; install it first.

#### Allow another certificate on your device

If you are trying to install someone else's SWU, you should install their certificate
as present in their `~/mkswu/swupdate.pem` file.

Note that this gives this person full rights over your device, if that is not what you intended we recommend rebuilding the swu from its .desc file yourself.

This can be updated by running any update after adding the certificate to your mkswu.conf as follow, and installing the generated `update_cert.swu` file:
```
[ATDE9 ~]$ cp <newcertificate> ~/mkswu/swupdate-bob.pem
[ATDE9 ~]$ vi ~/mkswu/mkswu.conf
# (at the end of the file)
# Bob's certificate to authorize
PUBKEY="$PUBKEY,$CONFIG_DIR/swupdate-bob.pem"
# This controls if we should update certificates on device, and can be
# removed once all devices have been updated to only allow new certificate
UPDATE_CERTS=yes
[ATDE9 ~]$ vi update_cert.desc
# force a rootfs update, if needed again increase version
swdesc_option version=1
swdesc_command --extra-os true
[ATDE9 ~]$ mkswu update_cert.swu
Successfully generated update_cert.swu
```

You can then unset `UPDATE_CERTS` in mkswu.conf.

If the update is only required for a single device, you can also directly copy/paste the new certificate in `/etc/swupdate.pem`; the certificate will not be removed unless `UPDATE_CERTS` is used in a SWU.

#### Reinstall another `initial_setup.swu` [↑](#index) {#reinstall_initial_setup}

Should you need to reinstall the initial setup, for example if you lost your old key files, there are two files to modify on your device:

* Add `/usr/share/mkswu/swupdate-onetime-public.pem` back to your device's `/etc/swupdate.pem`
* Remove the `extra_os.initial_setup` version from `/etc/sw-versions`

Once that is done `initial_setup.swu` should successfully install again.


## ZSTD\_decompressStream failed [↑](#index) {#bad_enc}

### Full log messages

```
Apr  4 11:27:09 armadillo user.info swupdate: START Software Update started !
Apr  4 11:27:09 armadillo user.err swupdate: FAILURE ERROR : ZSTD_decompressStream failed: Unknown frame descriptor
Apr  4 11:27:09 armadillo user.err swupdate: FAILURE ERROR : Error copying extracted file
Apr  4 11:27:09 armadillo user.err swupdate: FAILURE ERROR : Error streaming scripts_pre.sh.zst.enc
Apr  4 11:27:09 armadillo user.err swupdate: FATAL_FAILURE Image invalid or corrupted. Not installing ...
Apr  4 11:27:09 armadillo user.info swupdate: IDLE Waiting for requests...
```

### Cause of error

There are two possible causes for this error:

* a memory or disk corruption cause an archive to really become corrupted.  
If you think that might be the case, remove the hidden cache directory (`file.swu` will have a `.file` directory) and run mkswu again.

* The encryption key used for encryption differs from that on the device.  
Encryption in swupdate is done with AES-256-CBC which does not guarantee data integrity (like e.g. AES-GCM would), so swupdate cannot tell if a different key was used for encryption, and the decrypted result will be an invalid archive.  
If encryption was enabled, the key used for encryption is present in `~/mkswu/swupdate.aes-key` on your computer and `/etc/swupdate.aes-key` on the device.  
There can only be a single key installed at a time on the device, but non-encrypted updates can be installed even if a key is listed.

### How to fix

Compare the content of `~/mkswu/swupdate.aes-key` on your computer and `/etc/swupdate.aes-key` on your device:
```
[ATDE9 ~]$ cat ~/mkswu/swupdate.pem
f15cbadd4af07f15c8cfa33735d7ed22fc5d66bc2ea2fd815e622bf7208f1585 0027320dc17cc4cb3a05d690401a739b
armadillo:~# cat /etc/swupdate.aes-key
975f5768160c7a212403bfb3b8e4a4651b56f36f9e8ad17fdaee22b4b05fef46 ce7837e064ba8986f05c9281d2a9377d
```

If the keys differ as above, you can copy/paste the new key manually or install the new key with a SWU crafted to use no encryption or the old key:
```
[ATDE9 ~]$ vi old_swupdate.aes-key
975f5768160c7a212403bfb3b8e4a4651b56f36f9e8ad17fdaee22b4b05fef46 ce7837e064ba8986f05c9281d2a9377d
[ATDE9 ~]$ vi update_encryption_key.desc
# override encryption key to use for this SWU
# if set to the empty string "" then no encryption will be used
swdesc_option ENCRYPT_KEYFILE=test.aes-key
swdesc_option version=1

swdesc_files --extra-os --dest=/etc "$HOME/mkswu/swupdate.aes-key"
[ATDE9 ~]$ mkswu update_encryption_key.desc
Successfully generated update_encryption_key.swu
```

## no key provided for decryption [↑](#index) {#no_encryption_key}

### Full log messages

```
Oct  18 9:46:09 armadillo user.info swupdate: START Software Update started !
Oct  18 9:46:09 armadillo user.err swupdate: FAILURE ERROR : no key provided for decryption!
Oct  18 9:46:09 armadillo user.err swupdate: FAILURE ERROR : decrypt initialization failure, aborting
Oct  18 9:46:09 armadillo user.err swupdate: FAILURE ERROR : Error copying extracted file
Oct  18 9:46:09 armadillo user.err swupdate: FAILURE ERROR : Error streaming scripts_pre.sh.zst.enc
Oct  18 9:46:09 armadillo user.err swupdate: FATAL_FAILURE Image invalid or corrupted. Not installing ...
Oct  18 9:46:09 armadillo user.info swupdate: IDLE Waiting for requests...
```

### Cause of error

The SWU has been encrypted, but no decryption key is configured on the device.
For example, an encryption key has been generated after `initial_setup.swu` was first generated, and the key has not been installed as it should have been.

### How to fix

Install an `initial_setup.swu` with the appropriate keys.

First update the SWU on ATDE to ensure the key is present:
```
[ATDE9 ~]$ mkswu ~/mkswu/initial_setup.desc
Successfully generated /home/atmark/mkswu/initial_setup.swu
```

Then install it on armadillo as described in [reinstall another `initial_setup.swu`](#reinstall_initial_setup)

## No space left on device [↑](#index) {#filesystem_full}

### Full log messages

```
Apr  4 13:32:55 armadillo user.info swupdate: START Software Update started !
Apr  4 13:32:55 armadillo user.info swupdate: RUN [read_lines_notify] : No base os update: copying current os over
Apr  4 13:33:10 armadillo user.err swupdate: FAILURE ERROR : archive_write_data_block(): Write failed for 'largefile': No space left on device
Apr  4 13:33:12 armadillo user.err swupdate: FAILURE ERROR : copyimage status code is -14
Apr  4 13:33:12 armadillo user.err swupdate: FAILURE ERROR : Error streaming ___largefile_29bd3137e34574828fe82ed45760622934ba64ec.tar.zst.enc
Apr  4 13:33:12 armadillo user.err swupdate: FATAL_FAILURE Image invalid or corrupted. Not installing ...
Apr  4 13:33:12 armadillo user.info swupdate: IDLE Waiting for requests...
```

or

```
Apr  5 12:57:04 armadillo user.info swupdate: START Software Update started !
Apr  5 12:57:04 armadillo user.err swupdate: FAILURE ERROR : cannot write 16384 bytes: No space left on device
Apr  5 12:57:04 armadillo user.err swupdate: FAILURE ERROR : Error copying extracted file
Apr  5 12:57:04 armadillo user.err swupdate: FAILURE ERROR : Error streaming scripts_pre.sh.zst.enc
Apr  5 12:57:04 armadillo user.err swupdate: FATAL_FAILURE Image invalid or corrupted. Not installing ...
Apr  5 12:57:04 armadillo user.info swupdate: IDLE Waiting for requests...
```


### Cause of error

`archive_write_data_block(): Write failed` means that an archive could not be extracted, this usually means the rootfs or application volume is full.

Note that with older versions of swupdate the `No space left on device` message is not printed, so the error might be somewhere else in this case.

### How to fix

Immediately after this error `/target` will still have the target filesystem mounted, so you can check which filesystem was full with `df -h`.

* If rootfs (`/target`) was full, you probably need to make the rootfs content smaller, or use container spaces (`/var/app/volumes` or `/var/app/rollback/volumes`) instead.
* If appfs (`/var/app/volumes` and other application mounts) was full, you need to make some space.
  * In some case there can be leftover podman files in `/var/tmp` that can safely be removed. They are otherwise removed automatically on boot.
  * Remove data from `/var/app/volumes` and `/var/app/rollback/volumes`. Note that the rollback volumes directory has just been snapshoted so df will not immediately see free space, but space will be reclaimed when swupdate runs again
  * In case container images are full, use `abos-ctrl podman-rw` to remove unused containers. Like above, space will be reclaimed when swupdate runs due to the snapshot mechanism.  
In some case it might not be possible to hold two copies of the container images (e.g. if a large image is replaced by another large image with no layer in common); but image sizes should consider the need for double-copy and should be designed to be able to hold two copies.  
Note that updating containers through 'apt upgrade' or similar upgrade mechanism adds more data without freeing the space associated with the old files due to the layer mechanism. Consider rebuilding from a new base image or using `podman build`'s `--squash-all` option to remove intermediate layers.

## Cleanup of old images failed [↑](#index) {#images_cleanup}

### Full log messages

```
Apr  4 13:12:03 armadillo user.info swupdate: START Software Update started !
Apr  4 13:12:04 armadillo user.info swupdate: RUN [read_lines_notify] : No base os update: copying current os over
Apr  4 13:12:18 armadillo user.info swupdate: RUN [read_lines_notify] : Command 'command podman --root /target/var/lib/containers/storage_readonly --storage-opt additionalimagestore= load -i /var/tmp//nginx_alpine_tar___T..odman_target_load__1_ebdbd185b9a3c3d7f974105113431aa964d9a892.zst.enc' output:
Apr  4 13:12:18 armadillo user.info swupdate: RUN [read_lines_notify] : Getting image source signatures
Apr  4 13:12:18 armadillo user.info swupdate: RUN [read_lines_notify] : Copying blob sha256:a0ed873166223e616a73a741261837b3c71d629369e9b6d642b9ed80f3678a16
Apr  4 13:12:18 armadillo user.info swupdate: RUN [read_lines_notify] : Copying blob sha256:1eabc85c096e2bcdc00918611e5904dd3bfc24dbb272098b7ae9bf4aee112f17
Apr  4 13:12:18 armadillo user.info swupdate: RUN [read_lines_notify] : Copying blob sha256:2058793985d3a54dbcf1209b85f8c905d1d4b596832aa322f458e350f3c7448a
Apr  4 13:12:18 armadillo user.info swupdate: RUN [read_lines_notify] : Copying blob sha256:9c80cb4621c8e309353627bbc76c808c218d5be1b0db7ff3308bcc8b5346e2e6
Apr  4 13:12:18 armadillo user.info swupdate: RUN [read_lines_notify] : Copying blob sha256:2039729ed793e4ff647d5475373c0bdd9db921f4900e321ff6846674a4b2c1e5
Apr  4 13:12:18 armadillo user.info swupdate: RUN [read_lines_notify] : Copying blob sha256:dd565ff850e7003356e2b252758f9bdc1ff2803f61e995e24c7844f6297f8fc3
Apr  4 13:12:18 armadillo user.info swupdate: RUN [read_lines_notify] : Copying config sha256:6721bbfe2e852b0165854a54e998f5e904314d25a2ca6082c021213ab750a6fc
Apr  4 13:12:18 armadillo user.info swupdate: RUN [read_lines_notify] : Writing manifest to image destination
Apr  4 13:12:18 armadillo user.info swupdate: RUN [read_lines_notify] : Storing signatures
Apr  4 13:12:18 armadillo user.info swupdate: RUN [read_lines_notify] : Loaded image: docker.io/library/nginx:alpine
Apr  4 13:12:19 armadillo user.info swupdate: RUN [read_lines_notify] : Removing unused containers
Apr  4 13:12:19 armadillo user.err swupdate: FAILURE ERROR : image mycontainer:v2.1.0 in /target/etc/atmark/containers/mycontainer.conf not found in image store !
Apr  4 13:12:19 armadillo user.err swupdate: FAILURE ERROR : ----------------------------------------------
Apr  4 13:12:19 armadillo user.err swupdate: FAILURE ERROR : /!\ cleanup of old images failed: mismatching configuration/container update?
Apr  4 13:12:19 armadillo user.err swupdate: FAILURE ERROR : ----------------------------------------------
Apr  4 13:12:19 armadillo user.err swupdate: FAILURE ERROR : Command failed: sh -c 'sh $1 ' -- /var/tmp//scripts_post.sh.zst.enc
Apr  4 13:12:19 armadillo user.err swupdate: FAILURE ERROR : Error streaming scripts_post.sh.zst.enc
Apr  4 13:12:19 armadillo user.err swupdate: FATAL_FAILURE Image invalid or corrupted. Not installing ...
Apr  4 13:12:19 armadillo user.info swupdate: IDLE Waiting for requests...
```

### Cause of error

This error happens when some images are configured to auto-start in `/etc/atmark/containers` config files, but no such container image was found.

If the update was installed then the containers could not be started, so the update fails.

### How to fix

Install the appropriate containers or fix the `set_image` directive of the bad container config (in the log above, `/target/etc/atmark/containers/mycontainer.conf`).

If autostart was not required, setting `set_autostart no` in the config file also disables this check.

## Could not load/pull container [↑](#index) {#bad_container}

### Full log messages

```
Apr  4 13:24:38 armadillo user.info swupdate: START Software Update started !
Apr  4 13:24:39 armadillo user.info swupdate: RUN [read_lines_notify] : Other fs up to date, skipping copy
Apr  4 13:24:39 armadillo user.info swupdate: RUN [read_lines_notify] : Command 'command podman --root /target/var/lib/containers/storage_readonly --storage-opt additionalimagestore= load -i /var/tmp//embed_container_ngin..odman_target_load__1_58cf87c0169095e3e5fc03a89f235baf780740e2.zst.enc' output:
Apr  4 13:24:39 armadillo user.info swupdate: RUN [read_lines_notify] : Error: payload does not match any of the supported image formats:
Apr  4 13:24:39 armadillo user.info swupdate: RUN [read_lines_notify] :  * oci: parsing "localhost/var/tmp//embed_container_ngin..odman_target_load__1_58cf87c0169095e3e5fc03a89f235baf780740e2.zst.enc": parsing named reference "localhost/var/tmp//embed_container_ngin..odman_target_load__1_58cf87c0169095e3e5fc03a89f235baf780740
Apr  4 13:24:39 armadillo user.info swupdate: RUN [read_lines_notify] : e2.zst.enc": invalid reference format
Apr  4 13:24:39 armadillo user.info swupdate: RUN [read_lines_notify] :  * oci-archive: creating temp directory: untarring file "/var/tmp/oci3510394571": unexpected EOF
Apr  4 13:24:39 armadillo user.info swupdate: RUN [read_lines_notify] :  * docker-archive: loading tar component manifest.json: unexpected EOF
Apr  4 13:24:39 armadillo user.info swupdate: RUN [read_lines_notify] :  * dir: open /var/tmp/embed_container_ngin..odman_target_load__1_58cf87c0169095e3e5fc03a89f235baf780740e2.zst.enc/manifest.json: not a directory
Apr  4 13:24:39 armadillo user.err swupdate: FAILURE ERROR : ----------------------------------------------
Apr  4 13:24:39 armadillo user.err swupdate: FAILURE ERROR : /!\ Could not load /var/tmp//embed_container_ngin..odman_target_load__1_58cf87c0169095e3e5fc03a89f235baf780740e2.zst.enc
Apr  4 13:24:39 armadillo user.err swupdate: FAILURE ERROR : ----------------------------------------------
Apr  4 13:24:39 armadillo user.err swupdate: FAILURE ERROR : Command failed: sh -c '${TMPDIR:-/var/tmp}/scripts/podman_target load $1' -- /var/tmp//embed_container_ngin..odman_target_load__1_58cf87c0169095e3e5fc03a89f235baf780740e2.zst.enc
Apr  4 13:24:39 armadillo user.err swupdate: FAILURE ERROR : Error streaming embed_container_ngin..odman_target_load__1_58cf87c0169095e3e5fc03a89f235baf780740e2.zst.enc
Apr  4 13:24:39 armadillo user.err swupdate: FATAL_FAILURE Image invalid or corrupted. Not installing ...
Apr  4 13:24:39 armadillo user.info swupdate: IDLE Waiting for requests...
```

or

```
Apr  4 13:25:53 armadillo user.info swupdate: START Software Update started !
Apr  4 13:25:53 armadillo user.info swupdate: RUN [read_lines_notify] : Other fs up to date, skipping copy
Apr  4 13:25:56 armadillo user.info swupdate: RUN [read_lines_notify] : Command 'command podman --root /target/var/lib/containers/storage_readonly --storage-opt additionalimagestore= pull -q docker.io/doesnotexist:alpine' output:
Apr  4 13:25:56 armadillo user.info swupdate: RUN [read_lines_notify] : Error: initializing source docker://doesnotexist:alpine: reading manifest alpine in docker.io/library/doesnotexist: errors:
Apr  4 13:25:56 armadillo user.info swupdate: RUN [read_lines_notify] : denied: requested access to the resource is denied
Apr  4 13:25:56 armadillo user.info swupdate: RUN [read_lines_notify] : unauthorized: authentication required
Apr  4 13:25:56 armadillo user.err swupdate: FAILURE ERROR : ----------------------------------------------
Apr  4 13:25:56 armadillo user.err swupdate: FAILURE ERROR : /!\ Could not pull docker.io/doesnotexist:alpine
Apr  4 13:25:56 armadillo user.err swupdate: FAILURE ERROR : ----------------------------------------------
Apr  4 13:25:56 armadillo user.err swupdate: FAILURE ERROR : Command failed: sh -c '${TMPDIR:-/var/tmp}/scripts/podman_target pull "docker.io/doesnotexist:alpine"' -- /var/tmp//_home_martinet_g4_mk.._doesnotexist_alpine__45d3a2f2f6ae67f87996acebed9fdf8c1647cca4
Apr  4 13:25:56 armadillo user.err swupdate: FAILURE ERROR : Error streaming _home_martinet_g4_mk.._doesnotexist_alpine__45d3a2f2f6ae67f87996acebed9fdf8c1647cca4
Apr  4 13:25:56 armadillo user.err swupdate: FATAL_FAILURE Image invalid or corrupted. Not installing ...
Apr  4 13:25:56 armadillo user.info swupdate: IDLE Waiting for requests...
```

### Cause of error

The `swdesc_embed_container`, `swdesc_usb_container` or `swdesc_pull_container` failed.

In the logs above, the first message was `swdesc_embed_container` including a bad archive that was not a container image, and the second message was `swdesc_pull_container` with an image name that does not exist.

It is important to read the 'info' messages above the error in this case, as podman itself will display the real reason of the failure. For example, if it says "No space left on device" then you should also check that the [No space left on device](#filesystem_full) section.

### How to fix

Double-check the arguments of `swdesc_*_container` commands are valid.  
In doubt try to call `podman load` or `podman pull` manually to check.

## Hardware is not compatible [↑](#index) {#hw_compat_not_found}

### Full log messages

```
Jan  1 09:30:11 armadillo user.info swupdate: START Software Update started !
Jan  1 09:30:11 armadillo user.err swupdate: FAILURE ERROR : HW compatibility not found
Jan  1 09:30:11 armadillo user.err swupdate: FAILURE ERROR : Found nothing to install
Jan  1 09:30:11 armadillo user.err swupdate: FAILURE ERROR : JSON File corrupted
Jan  1 09:30:11 armadillo user.err swupdate: FAILURE ERROR : no parser available to parse sw-description!
Jan  1 09:30:11 armadillo user.err swupdate: FAILURE ERROR : Compatible SW not found
```

### Cause of error

swupdate checks that the swu file has been built with the current hardware in mind through /etc/hwrevision.

For example, Armadillo IoT G4 will have this content:
```
armadillo:~# cat /etc/hwrevision
AGX4500 at1
```

With the above, swupdate checks two things:

* That mkswu's config `HW_COMPAT` matches `at1`. The default value is a regex allowing `at1` or `at1-*`, this might change if we provide incompatible updates in the future.
* That the update is compatible with `AGX4500`. By default, any value here are allowed, but updates provided by atmark force some values to avoid installing updates on incompatible hardware, so that for example someone will not be able to install an update meant for Armadillo IoT G4 on an Armadillo IoT A6E. This is specified with the mkswu `swdesc_* --board` option in desc files.

### How to fix

Check you are installing an update on the correct device. If this is an update you generated, check your `HW_COMPAT` and usage of `--board` options.

## Container image immediately removed [↑](#index) {#image_removed}

### Full log messages

```
Apr  4 13:16:07 armadillo user.info swupdate: START Software Update started !
Apr  4 13:16:08 armadillo user.info swupdate: RUN [read_lines_notify] : No base os update: copying current os over
Apr  4 13:16:23 armadillo user.info swupdate: RUN [read_lines_notify] : Command 'command podman --root /target/var/lib/containers/storage_readonly --storage-opt additionalimagestore= load -i /var/tmp//nginx_alpine_tar___T..odman_target_load__1_ebdbd185b9a3c3d7f974105113431aa964d9a892.zst.enc' output:
Apr  4 13:16:23 armadillo user.info swupdate: RUN [read_lines_notify] : Getting image source signatures
Apr  4 13:16:23 armadillo user.info swupdate: RUN [read_lines_notify] : Copying blob sha256:a0ed873166223e616a73a741261837b3c71d629369e9b6d642b9ed80f3678a16
Apr  4 13:16:23 armadillo user.info swupdate: RUN [read_lines_notify] : Copying blob sha256:9c80cb4621c8e309353627bbc76c808c218d5be1b0db7ff3308bcc8b5346e2e6
Apr  4 13:16:23 armadillo user.info swupdate: RUN [read_lines_notify] : Copying blob sha256:1eabc85c096e2bcdc00918611e5904dd3bfc24dbb272098b7ae9bf4aee112f17
Apr  4 13:16:23 armadillo user.info swupdate: RUN [read_lines_notify] : Copying blob sha256:dd565ff850e7003356e2b252758f9bdc1ff2803f61e995e24c7844f6297f8fc3
Apr  4 13:16:23 armadillo user.info swupdate: RUN [read_lines_notify] : Copying blob sha256:2039729ed793e4ff647d5475373c0bdd9db921f4900e321ff6846674a4b2c1e5
Apr  4 13:16:23 armadillo user.info swupdate: RUN [read_lines_notify] : Copying blob sha256:2058793985d3a54dbcf1209b85f8c905d1d4b596832aa322f458e350f3c7448a
Apr  4 13:16:23 armadillo user.info swupdate: RUN [read_lines_notify] : Copying config sha256:6721bbfe2e852b0165854a54e998f5e904314d25a2ca6082c021213ab750a6fc
Apr  4 13:16:23 armadillo user.info swupdate: RUN [read_lines_notify] : Writing manifest to image destination
Apr  4 13:16:23 armadillo user.info swupdate: RUN [read_lines_notify] : Storing signatures
Apr  4 13:16:23 armadillo user.info swupdate: RUN [read_lines_notify] : Loaded image: docker.io/library/nginx:alpine
Apr  4 13:16:23 armadillo user.info swupdate: RUN [read_lines_notify] : Removing unused containers
Apr  4 13:16:24 armadillo user.info swupdate: RUN [read_lines_notify] : 6721bbfe2e852b0165854a54e998f5e904314d25a2ca6082c021213ab750a6fc
Apr  4 13:16:24 armadillo user.warn swupdate: RUN [read_lines_notify] : ----------------------------------------------
Apr  4 13:16:24 armadillo user.warn swupdate: RUN [read_lines_notify] : WARNING: Container image docker.io/library/nginx:alpine was added in swu but immediately removed
Apr  4 13:16:24 armadillo user.warn swupdate: RUN [read_lines_notify] : WARNING: Please use it in /etc/atmark/containers if you would like to keep it
Apr  4 13:16:24 armadillo user.warn swupdate: RUN [read_lines_notify] : ----------------------------------------------
Apr  4 13:16:25 armadillo user.info swupdate: RUN [read_lines_notify] : swupdate triggering reboot!
```

### Cause of warning

Note this is not an error, the update was succesfully installed but the container image included in the SWU was immediately removed and will thus not be present after reboot.

The reason for removal is as described in the warning: no container configuration in `/etc/atmark/containers` used the image, so the cleanup mechanism removed it.

### How to fix

Either fix the existing containers `set_image` configuration if it was wrong, or if the image is not meant to be started automatically add a new config file with just `set_image <newimage>` and `set_autostart no` to disable autostart.

Note that since the update has been installed you will need to increase the version in the desc file to install it again.

## Swupdate stuck [↑](#index) {#stuck}

An update should never get stuck.

It is possible that the "Waiting for btrfs to flush deleted subvolumes" step takes a bit of time, there is a hard limit of 30 minutes to that step but it should generally finish in one minute unless a subvolume was mounted in an unexpected location.  
If you think that was a problem, check that the `btrfs subvolume sync` command is running and if so send `findmnt`'s output for support either on [the armadillo forum][armadillo_forum] or [github issues][github_issues].

[armadillo_forum]:https://armadillo.atmark-techno.com/forum/armadillo
[github_issues]:https://github.com/atmark-techno/mkswu/issues

Other steps might take time if a lot of data must be written, but must be confirmed in a case by case basis.


## No autoinstall [↑](#index) {#no_autoinstall}

SWU files present at the root of a removable storage (USB memory or SD card) should be installed automatically on Armadillo Base OS.

You should see the following messages in `/var/log/messages` when a device is plugged in:
```
Mar 24 10:52:13 armadillo user.notice swupdate-auto-update: Mounting sda1 on /mnt in private namespace
Mar 24 10:52:13 armadillo user.notice swupdate-auto-update: Trying update /mnt/update.swu
```

If the first message is missing, make sure the storage is recognized by the device (e.g. `dmesg`).  
If the first message is present but not the later make sure the SWU file is present at the root of the device, as subdirectories are not considered.

## Anything else [↑](#index) {#anything_else}

If an install fails for a reason not listed above please ask for advice on [the armadillo forum][armadillo_forum] or [github issues][github_issues], including a full debug log as obtained from:

```
armadillo:~# swupdate -v -i file.swu
```
