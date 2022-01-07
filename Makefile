# could be possible to handle wildcard of languages later
# https://stackoverflow.com/a/40881718

l = ja
translations = $(wildcard po/$(l)/*.po)
locales = $(patsubst po/$(l)/%.po,locale/$(l)/LC_MESSAGES/%.mo,$(translations))

pot = po/mkimage.pot

all: $(locales) $(pot)


po/mkimage.pot: mkimage.sh examples/enable_sshd.desc examples/hawkbit_register.desc
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
