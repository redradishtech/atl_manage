SHELL:=/bin/bash

CONFIGS = $(wildcard relay_per_recipient virtual_alias  virtual_alias_hash virtual sasl_passwd sender_relay blacklist canonical)

all: $(wildcard *.db) $(patsubst %,%.db,$(CONFIGS)) relay_monitoring message_size_limit
%.db: %
	postmap $<
	postfix reload


relay_monitoring: transport_maps relay_per_recipient.db

transport_maps: $(ATL_MANAGE)/templates/postfix/transport_maps
	@if [[ -z $$(postconf -h transport_maps) ]]; then cat $< >> main.cf; echo "Appending $< to main.cf"; fi

message_size_limit: $(ATL_MANAGE)/templates/postfix/message_size_limit
	@if (($$(postconf -h message_size_limit) < 50240000)); then cat $< >> main.cf; echo "Appending $< to main.cf"; fi

relay_per_recipient: $(ATL_MANAGE)/templates/postfix/relay_per_recipient
	cp $< $@

.PHONY: relay_monitoring transport_maps
