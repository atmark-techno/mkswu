---
title: よくあるエラー
lang: ja-JP
---

`swupdate` が失敗するよくある原因を挙げ、それぞれについて判別方法と対処方法を説明します。

`swupdate` の実行方法によらず、`/var/log/messages` にはログが残ります。SWU イメージのインストールが完了したにもかかわらず、インストールされてなかった場合は `swupdate` を検索してログを確認してください。

エラーが発生すると、いくつかのエラーメッセージが出力されます。この資料の目次では、最初に表示される「`ERROR`」メッセージを見出しにします。ハイフンラインで囲まれている、`/!\` で始まる行があればそのメッセージです。

例えば、以下の例では「`ERROR : /!\ Nothing to do -- failing on purpose to save bandwidth`」を検索してください。
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

## 目次 {#index}

それぞれの問題が分かるエラーメッセージ。

* [Nothing to do: アップデート内容がすでにインストールされている場合](#nothing_to_do)
  * `ERROR : /!\ Nothing to do -- failing on purpose to save bandwidth`
* [Signature verification failed: 署名確認が失敗する場合](#sign_fail)
  * `ERROR : Signature verification failed`
* [ZSTD\_decompressStream failed: ZSTD 圧縮が展開できない場合](#bad_enc)
  * `ERROR : ZSTD_decompressStream failed: Unknown frame descriptor`
* [no key provided for decryption!: Armadillo に暗号鍵がない場合](#no_encryption_key)
  * `ERROR : no key provided for decryption!`
* [No space left on device: ファイルシステムの容量が足りない場合](#filesystem_full)
  * `ERROR : archive_write_data_block(): Write failed for '<file>': No space left on device`
  * `ERROR : cannot write 16384 bytes: No space left on device`
* [Cleanup of old images failed: イメージと設定ファイルに不整合が発生した場合](#images_cleanup)
  * `ERROR : /!\ cleanup of old images failed: mismatching configuration/container update?`
* [Could not load/pull image: コンテナイメージのインストールが失敗する場合](#bad_container)
  * `ERROR : /!\ Could not load /var/tmp//.....`
  * `ERROR : /!\ Could not pull ....`
* [HW compatibility not found: ハードウェア適合性不一致の場合](#hw_compat_not_found)
  * `ERROR : HW compatibility not found`
* [/var/app/volumes が読み取り専用でエラーになる場合](#volumes_ro)
  * `ERROR : .... /var/app/volumes/...: Read-only file system`
* [Container image immediately removed: イメージがインストールされない場合](#image_removed)
  * `WARNING: Container image docker.io/library/nginx:alpine was added in swu but immediately removed`
* [Swupdate が終了しない場合](#stuck)
  * (swupdate が終了しない)
* [自動インストールが失敗する場合](#no_autoinstall)
  * (USB メモリを挿しても `/var/log/messages` にメッセージがない）
* [その他の問題の場合](#anything_else)
  * その他の問題


## Nothing to do: アップデート内容がすでにインストールされている場合 [↑](#index) {#nothing_to_do}

### エラー発生時の/var/log/messagesの内容

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

### エラーの概要

SWUイメージの内容がすでにインストールされている時に表示されるメッセージです。

SWUイメージにはバージョンが記載されており、一つのバージョンは一度しかインストールできません。 `mkswu --show ファイル.swu` で SWU ファイルに使われているバージョンを確認できます。

### 対処方法

以下に示すどちらかの方法で解決できます。

* `.desc` ファイルに記載されているバージョンを上げて、`mkswu` を再実行します。  
`--version <component> <version>` で設定されている場合は `<version>` の部分を上げてください。  
`swdesc_option version=...` で設定されている場合は `mkswu --update-version ファイル.desc` を使って自動更新も可能です。

* Armadillo にインストールされているバージョンは `/etc/sw-versions` ファイルに保存されています。このファイルのバージョンを下げるか削除してもインストール可能になりますが、この方法は推奨しません。


## Signature verification failed: 署名確認が失敗する場合 [↑](#index) {#sign_fail}

### エラー発生時の/var/log/messagesの内容

````
armadillo:~# grep swupdate /var/log/messages
Apr  4 11:25:24 armadillo user.info swupdate: START Software Update started !
Apr  4 11:25:24 armadillo user.err swupdate: FAILURE ERROR : Signature verification failed
Apr  4 11:25:24 armadillo user.err swupdate: FAILURE ERROR : Compatible SW not found
Apr  4 11:25:24 armadillo user.err swupdate: FATAL_FAILURE Image invalid or corrupted. Not installing ...
Apr  4 11:25:24 armadillo user.info swupdate: IDLE Waiting for requests...
````

### エラーの概要

SWU イメージは作成時に署名されていますが、署名に使われた証明書が Armadillo 上にありません。

署名に使用される鍵と証明書は `mkswu --init` コマンドで作成されて、ATDE9 の `~/mkswu/swupdate.{key,pem}` に保存されています。`initial_setup.swu` を Armadillo にインストールすると、ATDE9 の swupdate.pem のコピーが Armadillo の `/etc/swupdate.pem` にインストールされます。

このエラーの原因には次のようなものが考えられます：

* `initial_setup` がまだインストールされていない
* 他人が作成した SWU をインストールしようとしたが、その SWU に使われた証明書がインストールされていない。または、鍵を無くして `mkswu --init` で鍵と証明書を再作成した。

このエラーは `swdesc_usb_container` を使った場合に、コンテナの署名確認の時にも発生します。コンテナイメージはSWUイメージとは別に検証されます。container.tar.sig ファイルが container.tar の内容と一致しないか、誤った証明書で署名されている可能性があります。

また、`initial_setup.swu` がすでにインストールされている状態で、再度インストールしようとすると同じエラーが発生します。 `initial_setup.swu` は「誰でも使える署名鍵」を使って作成されるため、一度インストールすると認識されなくなります。もう一度インストールしたい場合は [`initial_setup.swu` を再インストールする](#reinstall_initial_setup) をご参照ください。

### 対処方法

まずは Armadillo と ATDE 上の証明書を確認します。

以下のログでは、証明書を `...` で省略表記しています。
鍵の作成に使用された `mkswu` のバージョンによってはコメントが無い場合もありますが、無視して構いません。証明書の内容を確認してください。

Armadillo 上での確認：
```
armadillo:~# cat /etc/swupdate.pem
# atmark-2
-----BEGIN CERTIFICATE-----
MIIBvzCCAWagAwIBAgIUfagaF9RAjO2+x54PMqIlZkain9MwCgYIKoZIzj0EAwIw
...
LAzCERFEjT1UH1NutbSZr5IFdQ==
-----END CERTIFICATE-----
# atmark-3
-----BEGIN CERTIFICATE-----
MIIBwTCCAWagAwIBAgIUXXINCBvN9qSiMBms8SNnRZ3BZG0wCgYIKoZIzj0EAwIw
...
LTteeyDeKJOYWXWvi9lRUx7jY6WR
-----END CERTIFICATE-----
# swupdate.pem: my common name
-----BEGIN CERTIFICATE-----
MIIBmjCCAUCgAwIBAgIUFdtuYdCX1QwMNdhj+7QD+AF/o3AwCgYIKoZIzj0EAwIw
...
or0V6H5NZjclceCmWjdX+m/lSma7OUA5AuUdFU1f
-----END CERTIFICATE-----
```

ATDE 上での確認:
```
[ATDE9 ~]$ cat ~/mkswu/swupdate.pem
# swupdate.pem: my common name
-----BEGIN CERTIFICATE-----
MIIBmjCCAUCgAwIBAgIUFdtuYdCX1QwMNdhj+7QD+AF/o3AwCgYIKoZIzj0EAwIw
...
or0V6H5NZjclceCmWjdX+m/lSma7OUA5AuUdFU1f
-----END CERTIFICATE-----
```

#### 最初の証明書が、ワンタイムの公開証明書である場合

Armadillo の `/etc/swupdate.pem` にワンタイムの公開証明書が残っている場合は、ログイン時または `abos-ctrl status` コマンド実行時に以下の警告が表示されます：
```
WARNING: swupdate onetime public certificate is present, anyone can access this device
WARNING: Please install initial_setup.swu (from mkswu --init),
WARNING: or remove the first certificate from /etc/swupdate.pem
```

これは、`initial_setup.swu` をインストールしていない事を表します。最初にインストールしてください。

#### Armadillo に他人の証明書を追加する

他の人が作成したSWUイメージをインストールする場合には、その人の証明書をインストールする必要があります。

他の人の証明書をインストールすると、その人に Armadillo に対する完全な権限が付与される点に注意してください。権限の付与を望まない場合は、.desc ファイルを取得して swu ファイルを再作成することを推奨します。

以下の手順で、その人の ATDE にある `~/mkswu/swupdate.pem` をコピーし、 `mkswu update_cert.swu` コマンドで自分の Armadillo に追加することができます。
```
[ATDE9 ~]$ cp <newcertificate> ~/mkswu/swupdate-taro.pem
[ATDE9 ~]$ vi ~/mkswu/mkswu.conf
# ファイルの最後
# たろうさんの証明書
PUBKEY="$PUBKEY,$CONFIG_DIR/swupdate-taro.pem"
# この変数を設定すると証明書を更新します。更新された後に
# この変数を削除して swupdate.pem を管理外にできます。
UPDATE_CERTS=yes
[ATDE9 ~]$ vi update_cert.desc
# OS のアップデートを指示します。また、必要に応じてバージョンを上げてください。
swdesc_option version=1
swdesc_command --extra-os true
[ATDE9 ~]$ mkswu update_cert.swu
update_cert.swu を作成しました。
```

上記コマンドを実行後は、`UPDATE_CERTS` を無効にしても構いません。

更新の対象となる Armadillo が一台だけの場合は、新しい証明書を Armadillo の `/etc/swupdate.pem` に直接コピーペーストしても構いません。設定ファイルに `UPDATE_CERTS` を有効にしない限りは証明書が更新されることはありません。

#### `initial_setup.swu` を再インストールする [↑](#index) {#reinstall_initial_setup}

鍵をなくした等の理由で `initial_setup.swu` を再インストールするには、

Armadillo 3.19.1-at.4 以降では、 `abos-ctrl certificates reset` コマンドを実行し Armadillo の証明書をリセットすることで `initial_setup.swu` を再インストールできるようになります。

それ以前のバージョンでは、以下の 2 つのファイルを編集してください：

* `/etc/swupdate.pem` に `/usr/share/mkswu/swupdate-onetime-public.pem` の内容を追加してください。
* `/etc/sw-versions` にある `extra_os.initial_setup` の行を削除してください。

以上で `initial_setup.swu` を再びインストールできるようになります。

## ZSTD\_decompressStream failed: ZSTD 圧縮が展開できない場合 [↑](#index) {#bad_enc}

### エラー発生時の/var/log/messagesの内容

```
Apr  4 11:27:09 armadillo user.info swupdate: START Software Update started !
Apr  4 11:27:09 armadillo user.err swupdate: FAILURE ERROR : ZSTD_decompressStream failed: Unknown frame descriptor
Apr  4 11:27:09 armadillo user.err swupdate: FAILURE ERROR : Error copying extracted file
Apr  4 11:27:09 armadillo user.err swupdate: FAILURE ERROR : Error streaming scripts_pre.sh.zst.enc
Apr  4 11:27:09 armadillo user.err swupdate: FATAL_FAILURE Image invalid or corrupted. Not installing ...
Apr  4 11:27:09 armadillo user.info swupdate: IDLE Waiting for requests...
```

### エラーの概要

このエラーには、二つの原因が考えられます：

* メモリまたはストレージの破損によって、アーカイブファイルのデータ化けが生じた場合。
SWU の隠しディレクトリ(`file.swu` の場合は `.file` ファイル) を削除してから再び mkswu を実行すれば解決される場合があります。

* 暗号化に使用した暗号鍵がArmadilloに保存されているのものと異なる場合。
swupdate での暗号化は、データの整合性を保証しない AES-256-CBC で行われます (AES-GCM のようにデータの整合性を保証しません)。その為、異なる鍵でも復号可能で、その結果は無効なアーカイブになります。
暗号化を有効にした場合は、ATDEの `~/mkswu/swupdate.aes-key`を使って暗号化し、Armadilloの `/etc/swupdate.aes-key` を使って復号します。
証明書とは異なり、`swupdate`が扱う事のできるキーは1つだけです。もし鍵を紛失しても、暗号化されていない更新プログラムはインストール可能です。

### 対処方法

ATDE の `~/mkswu/swupdate.aes-key` と Armadillo の `/etc/swupdate.aes-key` を比較します：
```
[ATDE9 ~]$ cat ~/mkswu/swupdate.pem
f15cbadd4af07f15c8cfa33735d7ed22fc5d66bc2ea2fd815e622bf7208f1585 0027320dc17cc4cb3a05d690401a739b
armadillo:~# cat /etc/swupdate.aes-key 
975f5768160c7a212403bfb3b8e4a4651b56f36f9e8ad17fdaee22b4b05fef46 ce7837e064ba8986f05c9281d2a9377d
```

上記の様にキーが異なる場合は、新しい鍵をコピーペーストするか、以下の手順でアップデートできます：
```
[ATDE9 ~]$ vi old_swupdate.aes-key
975f5768160c7a212403bfb3b8e4a4651b56f36f9e8ad17fdaee22b4b05fef46 ce7837e064ba8986f05c9281d2a9377d
[ATDE9 ~]$ vi update_encryption_key.desc
# この SWU ファイルに使われている鍵を上書きします。
# ここで "" と空の行を設定すると暗号化されません。
swdesc_option ENCRYPT_KEYFILE=test.aes-key
swdesc_option version=1

swdesc_files --extra-os --dest=/etc "$HOME/mkswu/swupdate.aes-key"
[ATDE9 ~]$ mkswu update_encryption_key.desc
update_encryption_key.swu を作成しました。
```

## no key provided for decryption!: Armadillo に暗号鍵がない場合 [↑](#index) {#no_encryption_key}

### エラー発生時の/var/log/messagesの内容

```
Oct  18 9:46:09 armadillo user.info swupdate: START Software Update started !
Oct  18 9:46:09 armadillo user.err swupdate: FAILURE ERROR : no key provided for decryption!
Oct  18 9:46:09 armadillo user.err swupdate: FAILURE ERROR : decrypt initialization failure, aborting
Oct  18 9:46:09 armadillo user.err swupdate: FAILURE ERROR : Error copying extracted file
Oct  18 9:46:09 armadillo user.err swupdate: FAILURE ERROR : Error streaming scripts_pre.sh.zst.enc
Oct  18 9:46:09 armadillo user.err swupdate: FATAL_FAILURE Image invalid or corrupted. Not installing ...
Oct  18 9:46:09 armadillo user.info swupdate: IDLE Waiting for requests...
```

### エラーの概要

暗号化に使用した暗号鍵が Armadillo に保存されていません。
例えば、`initial_setup.swu` をインストールした後に ATDE で暗号化の鍵を再生成した場合などにありえます。

### 対処方法

Armadillo に現在の鍵で作成した `initial_setup.swu` をインストールしてください。

鍵の情報を更新するため、ATDE で SWU を更新します：
```
[ATDE9 ~]$ mkswu ~/mkswu/initial_setup.desc
/home/atmark/mkswu/initial_setup.swu を作成しました。
```

インストールについては [`initial_setup.swu` を再インストールする](#reinstall_initial_setup)をご参照ください。

## No space left on device: ファイルシステムの容量が足りない場合 [↑](#index) {#filesystem_full}

### エラー発生時の/var/log/messagesの内容

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


### エラーの概要

`archive_write_data_block(): Write failed` というメッセージは、アーカイブを展開できなかった事を意味します。rootfs または appfs の容量が不足している可能性が高いです。

現在のバージョンの `swupdate` では、「No space left on device」というメッセージが表示されない場合があります。念の為、後述の対処方法を参照して、容量が不足していないか確認してください。

### 対処方法

インストールの失敗直後では、インストール対象のファイルシステムは `/target` にマウントされた状態になっています。 `df -h` コマンドなどで容量の確認ができます。

* rootfs (`/target`) の容量が足りない場合は、rootfsを小さくするか、コンテナのボリュームストレージ (`/var/app/volumes` と `/var/app/rollback/volumes`) を利用します。

* appfs (`/var/app/volumes` 等) の容量が足りない場合は、データを削除する等して小さくしてください。
  * まれに `/var/tmp` に `podman` の一時ファイルが残っている場合があります。これらのファイルは再起動時に削除されますが、手動でも削除することができます。
  * `/var/app/volumes` と `/var/app/rollback/volumes` からファイルを削除します。 rollback ボリュームは A-B ブートのための snapshot なのでファイルを削除しても df コマンドで確認できる容量が変わりませんが、次回アップデート後に容量が戻ります。
  * コンテナイメージが容量不足になった場合は、`abos-ctrl podman-rw`コマンドを利用して不要なコンテナを削除してください。上記と同じく snapshot の影響で、容量が戻るのはアップデート後です。
大きなイメージを、別の大きなイメージに入れ替えた場合は、二つのコンテナイメージのコピーが保持できない場合があります。A-B ブートのことを考慮し、サイズに余裕を持たせてください。
`apt upgrade` または同等のアップデートメカニズムを利用して更新を行った場合、古いソフトウェアが完全に削除されない為、データが増えます。新しくベースイメージから作り直すか、`podman build` コマンドの `--squash-all` オプションで中間レイヤーを削除してみてください。

## Cleanup of old images failed: イメージと設定ファイルに不整合が発生した場合 [↑](#index) {#images_cleanup}

### エラー発生時の/var/log/messagesの内容

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

### エラーの概要

設定ファイル `/etc/atmark/containers` にコンテナイメージを自動起動すると設定されていますが、そのイメージがストレージにない事を示します。

このアップデートのインストールが完了してしまうとコンテナが起動できなくなる為、アップデートに失敗します。

### 対処方法

足りないイメージをインストールするか、コンテナ設定ファイル (上記のログでは「 `/target/etc/atmark/containers/mycontainer.conf` 」)の `set_image` 設定を修正してください。

自動起動が不要な場合は設定ファイルに「 `set_autostart no` 」を設定してください。

## Could not load/pull image: コンテナイメージのインストールが失敗する場合 [↑](#index) {#bad_container}

### エラー発生時の/var/log/messagesの内容

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

または、

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

### エラーの概要

`swdesc_embed_container`、 `swdesc_usb_container` または `swdesc_pull_container` コマンドが失敗しました。

上記ログでは、最初のエラーでは `swdesc_embed_container` で正しいコンテナイメージでない事を示し、二つ目のエラーでは `swdesc_pull_container` でコンテナイメージが存在しない事を示します。

エラーの原因を把握するには、エラーの前に表示される info メッセージを確認して判断します。例えば、「No space left on device」とメッセージが表示された場合は、 [Filesystem full](#filesystem_full) を参照してください。

### 対処方法

`swdesc_*_container` コマンドの引数を確認してください。   
与えた引数に不安がある場合は、 `podman load` や `podman pull` コマンドを手動で実行してみてください。

## HW compatibility not found: ハードウェア適合性不一致の場合 [↑](#index) {#hw_compat_not_found}

### エラー発生時の/var/log/messagesの内容

```
Jan  1 09:30:11 armadillo user.info swupdate: START Software Update started !
Jan  1 09:30:11 armadillo user.err swupdate: FAILURE ERROR : HW compatibility not found
Jan  1 09:30:11 armadillo user.err swupdate: FAILURE ERROR : Found nothing to install
Jan  1 09:30:11 armadillo user.err swupdate: FAILURE ERROR : JSON File corrupted
Jan  1 09:30:11 armadillo user.err swupdate: FAILURE ERROR : no parser available to parse sw-description!
Jan  1 09:30:11 armadillo user.err swupdate: FAILURE ERROR : Compatible SW not found
```

### エラーの概要

swupdate コマンドはアップデートと Armadillo のハードウェア適合性を確認します。

Armadillo のハードウェア適合性の情報は /etc/hwrevision に記載されています。例えば、Armadillo IoT G4 は以下のとおりになります：
```
armadillo:~# cat /etc/hwrevision
AGX4500 at1
```

この値を元に、以下 2 点の確認を行います：

* mkswu のコンフィグ内の `HW_COMPAT` が `at1` と一致すること。初期値では `at1` と `at1-*` を許可します。古い Armadillo でインストールできなくなるアップデートを適用することになった場合は、この値を変更することで対応可能です。
* アップデートが `AGX4500` と適合性があること。デフォルトではチェックしません。Armadilloサイトで提供しているアップデートの場合は、別のハードウェアにインストールできないようにしています。例えば、Armadillo IoT G4 向けのアップデートは Armadillo IoT A6E でインストールできません。desc ファイルの `swdesc_* --board` オプションでインストール可能な型番を設定できます。

### 対処方法

Armadillo に正しいアップデートをインストールしているかを確認してください。
生成した swu の場合はコンフィグの `HW_COMPAT` と desc ファイルの `--board` オプションを確認してください。

## /var/app/volumes が読み取り専用でエラーになる場合 [↑](#index) {#volumes_ro}

### エラー発生時の/var/log/messagesの内容

```
May 24 14:23:56 armadillo user.info swupdate: START Software Update started !
May 24 14:23:56 armadillo user.info swupdate: RUN [install_single_image] : Installing pre_script
May 24 14:23:57 armadillo user.info swupdate: RUN [read_lines_notify] : No base os update: copying current os over
May 24 14:24:01 armadillo user.info swupdate: RUN [install_single_image] : Installing swdesc_command 'a=/var/app/vol; echo foo > ${a}umes/test2'
May 24 14:24:02 armadillo user.err swupdate: FAILURE ERROR : --: line 0: can't create /var/app/volumes/test2: Read-only file system
May 24 14:24:02 armadillo user.err swupdate: FAILURE ERROR : Command failed: podman run --net=host --rm -v ${TMPDIR:-/var/tmp}:${TMPDIR:-/var/tmp} --read-only -v /target/tmp:/tmp -v /target/var/app/volumes:/var/app/volumes -v /target/var/app/rollback/volumes:/var/app/rollback/volumes --rootfs /target sh -c 'a=/var/app/vol; echo foo > ${a}umes/test2' --  /var/tmp/sh__c__a__var_app_vo..____a_umes_test2_____ffc90829c01f6d735745a24a72d978528fa5c550
May 24 14:24:02 armadillo user.err swupdate: FAILURE ERROR : Error streaming _home_atmark_code_..____a_umes_test2_____8921f25e1eaff3d0f78ebb6b8c9c766e3df250e7
May 24 14:24:02 armadillo user.err swupdate: FATAL_FAILURE Image invalid or corrupted. Not installing ...
May 24 14:24:03 armadillo user.info swupdate: IDLE Waiting for requests...
May 24 14:24:03 armadillo user.err swupdate: FAILURE ERROR : SWUpdate *failed* !
```

### エラーの概要

mkswu バージョン 6.1 以降では、 /var/app/volumes が未使用だと判断した場合はマウントしないようになりました。

スクリプトからアクセスする場合は古い mkswu で生成された SWU イメージでエラーすることがあります。

また、/var/app/volumes の文字列が記載されていない場合も失敗します。

### 対処方法

新しい mkswu バージョンで SWU を再生成してみてください。 /var/app/volumes に関するワーニングが出力された場合にマウントされるようになります。

ワーニングが出力されなかった場合はどこかに「/var/app/volumes」の文字列を追加してください。

ただし、ワーニングに記載されているとおりに /var/app/volumes の内容を本機能でアップデートすることは危険ですので、 /var/app/rollback/volumes のみにアクセスするようにしてください。  
/var/app/volumes は起動されたアプリケーションからアクセスしてください。

## Container image immediately removed: イメージがインストールされない場合 [↑](#index) {#image_removed}

### エラー発生時の/var/log/messagesの内容

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

### 警告の概要

これはエラーではなく、警告です。更新プログラムは正常にインストールされましたが、イメージに含まれてるコンテナが削除された為、再起動後に見つけることができません。

削除の理由は警告メッセージに記載されている通り、設定ファイル`/etc/atmark/containers`から利用されていない為です。

### 対処方法

既存の設定ファイルの `set_image` 設定が間違っている場合は修正してください。また、イメージを自動起動する必要が無い場合は、「 `set_image <newimage>` 」と「 `set_autostart no` 」だけを指定した新しい設定ファイルを追加してください。

## Swupdate が終了しない場合 [↑](#index) {#stuck}

アップデートが終了しないのは `swupdate` か `mkswu` の不具合です。

「Waiting for btrfs to flush deleted subvolumes」の処理に少し時間かかる場合があります。最大30分の制限時間を設定していますが、ほとんどの場合は1分以内に完了します。この問題に該当した場合は「 `btrfs subvolume sync` 」プロセスが起動していることを確認し、 `findmnt` コマンドの出力を [Armadillo フォーラム][armadillo_forum] または [github issues][github_issues] に送ってください。

[armadillo_forum]:https://armadillo.atmark-techno.com/forum/armadillo
[github_issues]:https://github.com/atmark-techno/mkswu/issues

書き込むデータ量が多かったり、他の処理に時間がかかることもあり、対策はケースバイケースとなります。

## 自動インストールが失敗する場合 [↑](#index) {#no_autoinstall}

SWU ファイルを USB メモリか SD カードのルートに設置すると、自動的に Armadillo Base OS にインストールされます。

デバイスをArmadilloに接続すると `/var/log/messages` に以下のメッセージが表示されます：
```
Mar 24 10:52:13 armadillo user.notice swupdate-auto-update: Mounting sda1 on /mnt in private namespace
Mar 24 10:52:13 armadillo user.notice swupdate-auto-update: Trying update /mnt/update.swu
```

最初のメッセージが表示されない場合は、Armadillo がデバイスを認識してない可能性があります。`dmesg` コマンド等で確認してください。
最初のメッセージだけが表示されて `Trying update` で始まるメッセージが表示されない場合は、SWU ファイルがパーティションのルートに設置されていることを確認してください。サブディレクトリに入っている場合は自動アップデートが行なわれません。

## その他の問題の場合 [↑](#index) {#anything_else}

この資料を読んでも問題が解決しない場合は、 [Armadillo フォーラム][armadillo_forum] または [github issues][github_issues] に連絡してください。その際、以下のコマンドの出力を提供してください：
```
armadillo:~# swupdate -v -i file.swu
```
