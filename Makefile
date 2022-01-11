PREFIX = /usr
BIN = $(PREFIX)/bin
SHARE = $(PREFIX)/share/mkswu
LOCALEDIR = $(PREFIX)/share/locale

# could be possible to handle wildcard of languages later
# https://stackoverflow.com/a/40881718
l = ja
translations = $(wildcard po/$(l)/*.po)
locales = $(patsubst po/$(l)/%.po,locale/$(l)/LC_MESSAGES/%.mo,$(translations))
pot = po/mkswu.pot

# XXX install example data more cleanly
install_scripts = $(wildcard scripts/*sh) $(wildcard scripts/podman_*)
install_examples = $(wildcard examples/*desc) $(wildcard examples/*sh)
install_hawkbit = hawkbit/nginx_hawkbit.conf hawkbit/mysql_utf8.cnf hawkbit/docker-compose.yml hawkbit/create-update.sh hawkbit/.env


.PHONY: all install check

all: $(locales) $(pot)

po/mkswu.pot: mkswu examples/enable_sshd.desc examples/hawkbit_register.desc
	./po/update.sh $@ $^

po/$(l)/%.po: po/%.pot
	msgmerge -o $@ $@ $<

locale/$(l)/LC_MESSAGES/%.mo: po/$(l)/%.po
	@# restandardize po file formatting
	msgmerge -o $< $< $<
	@if grep -qx "#, fuzzy" $<; then \
		echo "$< has had fuzzy updates, please fix before updating!"; \
		false; \
	fi
	msgfmt -o $@ $<

check:
	./tests/run.sh

TAG ?= $(shell git describe --tags)
TARNAME = mkswu-$(TAG)

dist:
	@if ! [ -e .git ]; then \
		echo "make dist can only run within git directory"; \
		false; \
	fi
	@if ! git diff-index --ignore-submodules=untracked --quiet HEAD; then \
		echo "git index is not clean: please run make clean and check submodules"; \
		false; \
	fi
	git ls-files --recurse-submodules | \
		tar -cazf $(TARNAME).tar.gz --xform s:^:$(TARNAME)/: --verbatim-files-from -T-


install: all
	install -D -t $(DESTDIR)$(BIN) mkswu
	install -D -m 0644 -t $(DESTDIR)$(LOCALEDIR)/$(l)/LC_MESSAGES $(locales)
	install -D -m 0644 -t $(DESTDIR)$(SHARE) mkimage.conf.defaults
	install -D -m 0644 -t $(DESTDIR)$(SHARE) swupdate-onetime-public.key
	install -D -m 0644 -t $(DESTDIR)$(SHARE) swupdate-onetime-public.pem
	install -D -t $(DESTDIR)$(SHARE) swupdate_post.sh
	install -d $(DESTDIR)$(SHARE)/scripts
	@# use cp instead of install to preserve executable mode
	cp -t $(DESTDIR)$(SHARE)/scripts $(install_scripts)
	install -d $(DESTDIR)$(SHARE)/examples
	cp -t $(DESTDIR)$(SHARE)/examples $(install_examples)
	install -d $(DESTDIR)$(SHARE)/examples/nginx_start/etc/atmark/containers
	cp -t $(DESTDIR)$(SHARE)/examples/nginx_start/etc/atmark/containers examples/nginx_start/etc/atmark/containers/nginx.conf
	install -d $(DESTDIR)$(SHARE)/examples/enable_sshd/root/.ssh
	cp -t $(DESTDIR)$(SHARE)/examples/enable_sshd/root/.ssh examples/enable_sshd/root/.ssh/authorized_keys
	install -d $(DESTDIR)$(SHARE)/hawkbit
	cp -t $(DESTDIR)$(SHARE)/hawkbit $(install_hawkbit)
