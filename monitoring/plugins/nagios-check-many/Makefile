PLUGIN_DIR=$(DESTDIR)/usr/lib/nagios/plugins

all:
	@echo 'use "make install" to install, or "make deb" to build debian package'
	
install:
	test -d $(PLUGIN_DIR) || install -o root -g root -d $(PLUGIN_DIR)
	install -o root -g root -m 0755 check-many $(PLUGIN_DIR)
		
clean:
	find . -name "*~" -print0 | xargs -0r rm -f --

mrproper:
	dh clean
	
deb:
	debuild

checkdeb:
	cd .. && lintian --info `ls -1t *deb | head -n 1`

publish: all deb
	cd .. && reprepro include wheezy `ls -1t *.changes | head -n 1`
	git commit -a
	git push
