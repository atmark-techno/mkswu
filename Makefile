po/mkimage.pot: mkimage.sh examples/enable_sshd.desc examples/hawkbit_register.desc
	sed -e 's/info "\|error "/$$"/' < mkimage.sh | bash --dump-po-strings | sed -e 's/bash:/mkimage.sh:/' > po/mkimage.pot
	sed -e 's/info "\|error "/$$"/' < examples/enable_sshd.desc | bash --dump-po-strings | sed -e 's/bash:/enable_sshd.desc:/' >> po/mkimage.pot
	sed -e 's/info "\|error "/$$"/' < examples/hawkbit_register.desc | bash --dump-po-strings | sed -e 's/bash:/hawkbit_register.desc:/' >> po/mkimage.pot

locale/ja/LC_MESSAGES/mkimage.mo: po/ja/mkimage.po
	msgfmt -o $@ $<
