-include .env

ifndef GDRIVE
$(error GDRIVE env var is not set)
endif

UUID ?= $(shell uuidgen || (echo "uuidgen not found or failed" && exit 1))

gdrive_index.json:
	rclone lsjson --hash -R ${GDRIVE}  > $@

.PHONY: fetch_index
fetch_index: gdrive_index.json

.INTERMEDIATE: key_filename.tsv
key_filename.tsv: gdrive_index.json
	< $^ ./index2keys > $@

.INTERMEDIATE: key_object.tsv
key_object.tsv: key_filename.tsv
	cut -f1 key_filename.tsv | git annex examinekey --format='$${key}\t.git/annex/objects/$${hashdirmixed}$${key}/$${key}\n' --batch > $@

.INTERMEDIATE: key_url.tsv
key_url.tsv: key_filename.tsv
	< key_filename.tsv ./filename_key2url > $@

# This will be much simpler when I upgrade git-annex
.INTERMEDIATE: filename.tsv
filename.tsv: key_filename.tsv
	cut -f2 key_filename.tsv > $@

.INTERMEDIATE: filename_key_object.tsv
filename_key_object.tsv: filename.tsv key_object.tsv
	paste $? > $@

satellite:
	mkdir -p $@

# don't forget to take directly from lasatellite annex-init.sh...
init_repo: satellite
	cd satellite && ( git init && git annex reinit ${UUID} && git config annex.backend MD5 && git config annex.security.allowed-ip-addresses "::1" )
	cd satellite && ( git config annex.genmetadata true && git annex config --set annex.dotfiles false  )

make_symlinks: filename_key_object.tsv satellite
	cd satellite && pv ../filename_key_object.tsv | ../make_object_symlinks

add_links: make_symlinks init_repo satellite
	cd satellite && git add .

register_urls: key_url.tsv add_links init_repo
	cd satellite && pv ../key_url.tsv | git annex registerurl --batch

# Can also just do direct key name mapping...

finish_repo: register_urls
	cd satellite && git commit -m "Finished importing"

clean: clean_int_keys clean_repo

clean_repo:
	-chmod -R a+w satellite
	rm -rf satellite

clean_index:
	rm -f gdrive_index.json

clean_int_keys:
	rm -f filename_url.tsv key_object.tsv filename_object.tsv key_filename.tsv filename_key_object.tsv filename.tsv key_url.tsv

serve:
	 rclone serve webdav  ${GDRIVE} --etag-hash auto --addr 0.0.0.0:8356 --read-only --drive-chunk-size 512M

serve_rw:
	rclone serve webdav  ${GDRIVE} --etag-hash auto --addr 0.0.0.0:8356

satellite_serve_webdav_buffered:
	 rclone serve webdav  ${GDRIVE} --etag-hash auto --addr 0.0.0.0:8356 --read-only --vfs-cache-mode full

satellite_serve_http:
	 rclone serve http  ${GDRIVE} --addr 0.0.0.0:8356 --read-only

satellite_serve_http_buffered:
	 rclone serve http  ${GDRIVE} --addr 0.0.0.0:8356 --read-only --vfs-cache-mode full
