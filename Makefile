# Makefile to easily build all needed tools

BINS = e2fsck resize2fs tune2fs truncate

$(BINS):
	./make_e2fstools

clean:
	rm -f $(BINS)

install:
	install -d /usr/local/bin
	install -m 755 e2fsck /usr/local/bin
	install -m 755 resize2fs /usr/local/bin
	install -m 755 tune2fs /usr/local/bin
	install -m 755 pishrink /usr/local/bin
	install -m 755 truncate /usr/local/bin

uninstall:
	rm -f /usr/local/bin/e2fsck /usr/local/bin/resize2fs /usr/local/bin/tune2fs /usr/local/bin/pishrink /usr/local/bin/truncate
