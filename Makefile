# could be possible to handle wildcard of languages later
# https://stackoverflow.com/a/40881718

l = ja
translations = $(wildcard po/$(l)/*.po)
locales = $(patsubst po/$(l)/%.po,locale/$(l)/LC_MESSAGES/%.mo,$(translations))

pot = $(wildcard po/*.pot)

all: $(locales) $(pot)


po/mkimage.pot: mkimage.sh examples/enable_sshd.desc examples/hawkbit_register.desc
	sed -e 's/info "\|error "/$$"/' < mkimage.sh | bash --dump-po-strings | sed -e 's/bash:/mkimage.sh:/' > po/mkimage.pot
	sed -e 's/info "\|error "/$$"/' < examples/enable_sshd.desc | bash --dump-po-strings | sed -e 's/bash:/enable_sshd.desc:/' >> po/mkimage.pot
	sed -e 's/info "\|error "/$$"/' < examples/hawkbit_register.desc | bash --dump-po-strings | sed -e 's/bash:/hawkbit_register.desc:/' >> po/mkimage.pot

po/init.pot: init.sh
	bash --dump-po-strings $< > $@

locale/$(l)/LC_MESSAGES/%.mo: po/$(l)/%.po
	msgfmt -o $@ $<
