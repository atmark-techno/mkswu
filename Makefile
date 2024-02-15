PREFIX ?= /usr
BIN = $(PREFIX)/bin
SHARE = $(PREFIX)/share/mkswu
LOCALEDIR = $(PREFIX)/share/locale
LIBEXEC = $(PREFIX)/libexec/mkswu
BASH_COMPLETION_DIR = $(PREFIX)/share/bash-completion/completions

# could be possible to handle wildcard of languages later
# https://stackoverflow.com/a/40881718
l = ja
translations = $(wildcard po/$(l)/*.po)
locales = $(patsubst po/$(l)/%.po,locale/$(l)/LC_MESSAGES/%.mo,$(translations))

# XXX install example data more cleanly
install_scripts = $(wildcard scripts/*sh) $(wildcard scripts/podman_*)
install_completions = $(wildcard bash_completion.d/*)
install_examples = $(wildcard examples/*desc) $(wildcard examples/*sh)
install_hawkbit = hawkbit-compose/setup_container.sh hawkbit-compose/fragments
install_docs = $(wildcard docs/*md)
install_docs_html = $(patsubst docs/%.md,docs/%.html,$(install_docs))


.PHONY: all install install_swupdate check clean locales doc

all: locales

locales: $(locales)

doc: $(install_docs_html)

clean:
	rm -rf tests/out
	@# tests input
	rm -f tests/zoo/* tests/mkswu-aes.conf tests/swupdate.aes-key
	rm -f examples/nginx_start.tar imx-boot_armadillo_x2 examples/linux-at-5.10.9-r3.apk
	rm -rf examples/kernel
	rm -f docs/*.html


po/mkswu.pot: mkswu examples/enable_sshd.desc examples/hawkbit_register.desc
	./po/update.sh $@ $^

po/mkimage.pot: mkimage.sh
	./po/update.sh $@ $^

po/hawkbit_setup_container.pot: hawkbit-compose/setup_container.sh
	./po/update.sh $@ $^

po/mkswu_kernel_update_plain.pot: examples/kernel_update_plain.install.sh
	./po/update.sh $@ $^

po/$(l)/%.po: po/%.pot
	msgmerge --no-wrap -o $@ $@ $<

locale/$(l)/LC_MESSAGES/%.mo: po/$(l)/%.po
	@# restandardize po file formatting
	msgmerge --no-wrap -o $< $< $<
	@if grep -qx "#, fuzzy" $<; then \
		echo "$< has had fuzzy updates, please fix before updating!"; \
		false; \
	fi
	msgfmt -o $@ $<

docs/%.html: docs/%.md
	pandoc -s $< -o $@

check:
	./tests/run.sh

TAG ?= $(subst -,.,$(shell git describe --tags 2>/dev/null || cat .version))

TARNAME = mkswu_$(TAG)

dist: all
	@if ! [ -e .git ]; then \
		echo "make dist can only run within git directory"; \
		false; \
	fi
	@git update-index --refresh
	@if ! git diff-index --ignore-submodules=untracked --quiet HEAD; then \
		echo "git index is not clean: please run make clean and check submodules"; \
		false; \
	fi
	echo $(TAG) > .version
	{ git ls-files --recurse-submodules; echo ".version"; } | \
		tar -caJf $(TARNAME).orig.tar.xz --xform "s:^:$(TARNAME)/:S" --verbatim-files-from -T-
	git ls-files hawkbit-compose | \
		tar -caJf hawkbit-compose-$(TAG).tar.xz --xform "s:^hawkbit-compose:hawkbit-compose-$(TAG):S" --verbatim-files-from -T-

install: install_mkswu install_examples install_locales install_hawkbit_compose install_html

install_mkswu:
	install -D -t $(DESTDIR)$(BIN) mkswu hawkbit_push_update
	sed -i -e "s/MKSWU_VERSION=\"/&$(TAG)/" $(DESTDIR)$(BIN)/mkswu
	install -D -t $(DESTDIR)$(BIN) podman_partial_image
	install -D -m 0644 -t $(DESTDIR)$(SHARE) mkswu.conf.defaults
	install -D -m 0644 -t $(DESTDIR)$(SHARE) swupdate-onetime-public.key
	install -D -m 0644 -t $(DESTDIR)$(SHARE) swupdate-onetime-public.pem
	install -d $(DESTDIR)$(SHARE)/certs
	install -D -m 0644 -t $(DESTDIR)$(SHARE)/certs certs/atmark*.pem
	install -D -m 0644 -t $(DESTDIR)$(BASH_COMPLETION_DIR) $(install_completions)
	install -D -t $(DESTDIR)$(SHARE) scripts_pre.sh scripts_post.sh
	install -d $(DESTDIR)$(SHARE)/scripts
	@# use cp instead of install to preserve executable mode
	cp -t $(DESTDIR)$(SHARE)/scripts $(install_scripts)

install_examples:
	install -d $(DESTDIR)$(SHARE)/examples
	cp -t $(DESTDIR)$(SHARE)/examples $(install_examples)
	install -d $(DESTDIR)$(SHARE)/examples/nginx_start/etc/atmark/containers
	cp -t $(DESTDIR)$(SHARE)/examples/nginx_start/etc/atmark/containers examples/nginx_start/etc/atmark/containers/nginx.conf
	install -d $(DESTDIR)$(SHARE)/examples/enable_sshd/root/.ssh
	cp -t $(DESTDIR)$(SHARE)/examples/enable_sshd/root/.ssh examples/enable_sshd/root/.ssh/authorized_keys
	install -d $(DESTDIR)$(SHARE)/examples/uboot_env
	cp -t $(DESTDIR)$(SHARE)/examples/uboot_env examples/uboot_env/bootdelay
	install -d $(DESTDIR)$(SHARE)/examples/armadillo-twin
	cp -t $(DESTDIR)$(SHARE)/examples/armadillo-twin \
		examples/armadillo-twin/*.desc

install_locales: locales
	install -D -m 0644 -t $(DESTDIR)$(LOCALEDIR)/$(l)/LC_MESSAGES locale/ja/LC_MESSAGES/mkswu.mo

install_hawkbit_compose:
	install -d $(DESTDIR)$(SHARE)/hawkbit-compose
	install -D -m 0644 -t $(DESTDIR)$(LOCALEDIR)/$(l)/LC_MESSAGES hawkbit-compose/locale/ja/LC_MESSAGES/hawkbit_setup_container.mo
	cp -rt $(DESTDIR)$(SHARE)/hawkbit-compose $(install_hawkbit)

install_html: $(install_docs_html)
	install -d $(DESTDIR)$(SHARE)/docs
	cp -t $(DESTDIR)$(SHARE)/docs $(install_docs_html)

# this target is not part of normal install
install_swupdate:
	install -d $(DESTDIR)$(LIBEXEC)
	cp -t $(DESTDIR)$(LIBEXEC) $(install_scripts)
	cp scripts_post.sh $(DESTDIR)$(LIBEXEC)/post.sh
	# remove self-decompress
	sed -e '/BEGIN_ARCHIVE/d' scripts_pre.sh > $(DESTDIR)$(LIBEXEC)/pre.sh
	chmod +x $(DESTDIR)$(LIBEXEC)/pre.sh
	# modify skip install hook
	sed -i -e 's/DEBUG_SKIP_SCRIPTS/DEBUG_SKIP_VENDORED_SCRIPTS/' $(DESTDIR)$(LIBEXEC)/common.sh
	# modify scripts base directory
	sed -i -e 's:^SCRIPTSDIR=.*:SCRIPTSDIR=$(LIBEXEC):' \
		-e 's/^MKSWU_TMP=.*/&-vendored/' \
		$(DESTDIR)$(LIBEXEC)/pre.sh \
		$(DESTDIR)$(LIBEXEC)/post.sh \
		$(DESTDIR)$(LIBEXEC)/cleanup.sh
	# record version
	echo "$(TAG)" > $(DESTDIR)$(LIBEXEC)/version
