# Makefile to easily build all needed tools

BINS = e2fsck resize2fs tune2fs

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
