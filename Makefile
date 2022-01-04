# could be possible to handle wildcard of languages later
# https://stackoverflow.com/a/40881718

l = ja
translations = $(wildcard po/$(l)/*.po)
locales = $(patsubst po/$(l)/%.po,locale/$(l)/LC_MESSAGES/%.mo,$(translations))

pot = po/mkimage.pot po/genkey.pot po/init.pot

all: $(locales) $(pot)


po/mkimage.pot: mkimage.sh examples/enable_sshd.desc examples/hawkbit_register.desc
	./po/update.sh $@ $^

po/genkey.pot: genkey.sh
	./po/update.sh $@ $^

po/init.pot: init.sh
	./po/update.sh $@ $^

po/$(l)/%.po: po/%.pot
	msgmerge -o $@ $@ $<

locale/$(l)/LC_MESSAGES/%.mo: po/$(l)/%.po
	msgfmt -o $@ $<
