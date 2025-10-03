.PHONY: docs pubdocs

docfiles = $(shell ls docs/*.markdown)

# Documentation ---------------------------------------------------------------
docs/build/index.html: $(docfiles) docs/title
	cd docs && ~/.virtualenvs/d/bin/d

docs: docs/build/index.html

pubdocs: docs
	hg -R ~/src/docs.stevelosh.com pull -u
	rsync --delete -a ./docs/build/ ~/src/docs.stevelosh.com/hg-prompt
	hg -R ~/src/docs.stevelosh.com commit -Am 'hg-prompt: Update site.'
	hg -R ~/src/docs.stevelosh.com push
