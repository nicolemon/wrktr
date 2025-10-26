USER_BIN := /usr/local/bin
USER_SHARE := /usr/local/share

wrktr:
	cp wrktr.sh wrktr

install: wrktr
	chmod +x wrktr
	sudo install wrktr $(USER_BIN)/wrktr

uninstall:
	@[ -f $(USER_BIN)/wrktr ] && (sudo rm $(USER_BIN)/wrktr; echo "uninstalled from $(USER_BIN)") || echo "wrktr not installed"

.PHONY: install uninstall
# vim:ft=make
#
