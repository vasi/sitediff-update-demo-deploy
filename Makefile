NAME = sitediff-update-demo
BRANCH = master
REPO = evolvingweb/$(NAME)

all: build run update_run sitediff sitediff_serve

all_rm: rm update_rm


ifneq ($(REPO),)

REMOTE = git@gitlab.***REMOVED***.ca:$(REPO).git

assets/code:
	git clone -b $(BRANCH) $(REMOTE) $@

else

assets/code: assets/drupal.tar.gz
	mkdir $@
	tar -C $@ -xf $< --strip-components 1
	cp $@/sites/default/default.settings.php $@/sites/default/settings.php
	echo "require_once 'settings.local.php';" >> $@/sites/default/settings.php
	cp files/gitignore $@/.gitignore
	find $@ -type f -perm +0100 -exec chmod a-x {} +
	git -C $@ init
	git -C $@ add .
	git -C $@ commit -m 'Initial commit'

endif

# Download the most recent drupal
assets/drupal.tar.gz:
	url=$$(curl -s http://updates.drupal.org/release-history/drupal/7.x | perl -ne 'if (m,http://\S+\.tar\.gz,) { print "$$&\n"; exit }'); \
	wget $$url -O $@

assets/drupal.sql:
	touch $@

assets/files:
	mkdir -p assets/files

assets/settings.local.php: files/settings.local.php assets/mysql_drupal_pass
	cat $< | \
	sed -e "s/@@PASSWORD@@/$$(cat assets/mysql_drupal_pass)/" \
	> $@

assets/authorized_keys:
	ssh-add -L > $@

assets/mysql_root_pass assets/mysql_drupal_pass assets/drupal_admin_pass: %:
	pwgen -1 16 > $@

assets/composer.phar:
	wget -O $@ http://getcomposer.org/composer.phar

assets/uid:
	id -u > $@
assets/gid:
	id -g > $@

assets/docker_host_ip:
	hostname -I | awk '{print $$1}' > $@

assets/site_name:
	echo $(NAME) > $@

assets_dir:
	mkdir -p assets

assets: assets_dir assets/code assets/files assets/settings.local.php assets/mysql_root_pass assets/mysql_drupal_pass assets/composer.phar assets/authorized_keys assets/uid assets/gid assets/docker_host_ip assets/drupal_admin_pass assets/drupal.sql assets/site_name

PULL_DIR = .
pull_real:
	cd $(PULL_DIR); \
	if ! git diff-files --quiet; then \
		git stash; \
		changes=yes; \
	fi; \
	git pull --rebase; \
	if [ "$$changes" = yes ]; then \
		git stash pop; \
	fi
pull: pull_real
	$(MAKE) pull_real PULL_DIR=assets/code

IMAGE = evolvingweb/$(NAME)
CONTAINER = $(NAME)
DOCKER_HOSTNAME = docker
SSH_PORT = 9103
HTTP_PORT = 9180
PORTS = -p $(HTTP_PORT):80 -p $(SSH_PORT):22
RUN_OPTS = -d
BUILD_OPTS =
RUN = docker run $(PORTS) $(LINKS) $(RUN_OPTS) --name=$(CONTAINER)
RUN_CMD =
MOUNTS =

build: assets
	docker build $(BUILD_OPTS) -t $(IMAGE) .

# launch debug shell in latest (intermediate) image; useful if 'docker build' fails
debug_latest:
	docker run -t -i `docker images -q | head -n 1` /bin/bash

run:
	$(RUN) $(IMAGE) $(RUN_CMD)
run_mounted:
	$(RUN) $(MOUNTS) $(IMAGE) $(RUN_CMD)

rm: stop
	docker rm $(CONTAINER)

start:
	docker start $(CONTAINER)

stop:
	docker stop $(CONTAINER)

SSH_USER = docker
SSH_CMD =
ssh:
	ssh -p $(SSH_PORT) -o ForwardAgent=yes -o NoHostAuthenticationForLocalhost=yes -l $(SSH_USER) localhost $(SSH_CMD)

# Destroys all uncommitted changes, keeps .vagrant folder
clean:
	git clean -ixd -e .vagrant/ :/

# Destroys all containers and caches that aren't running or tagged!
obliterate:
	-docker ps -a -q | sort | xargs docker rm
	-docker images -a | grep "^<none>" | awk '{print $$3}' | xargs docker rmi

drush_uli:
	make drush DRUSH_CMD="uli -l $(DOCKER_HOSTNAME):$(HTTP_PORT)"

DRUSH_CMD =
drush:
	make ssh SSH_CMD="'cd /drupal/site; drush $(DRUSH_CMD)'"

BACKUP_DIR =
backup:
	mkdir -p '$(BACKUP_DIR)'
	docker exec $(CONTAINER) mysqldump -u drupal -p"$$(cat assets/mysql_drupal_pass)" drupal > '$(BACKUP_DIR)/dump.sql'
	docker exec $(CONTAINER) tar -C /drupal/site/sites/default -cf - files > '$(BACKUP_DIR)/files.tar'


update_drupal:
	$(MAKE) drush DRUSH_CMD="up -y drupal"

UPDATE_CONTAINER = $(CONTAINER)_update
UPDATE_SSH_PORT = 9104
UPDATE_HTTP_PORT = 9181
UPDATE_MAKE = $(MAKE) CONTAINER=$(UPDATE_CONTAINER) SSH_PORT=$(UPDATE_SSH_PORT) HTTP_PORT=$(UPDATE_HTTP_PORT)

update_run:
	$(UPDATE_MAKE) run
	sleep 3
	$(UPDATE_MAKE) update_drupal
update_rm:
	$(UPDATE_MAKE) rm

sitediff:
	sitediff diff \
		--before=http://localhost:$(HTTP_PORT) \
		--after=http://localhost:$(UPDATE_HTTP_PORT) \
		--before-report=http://$(DOCKER_HOSTNAME):$(HTTP_PORT) \
		--after-report=http://$(DOCKER_HOSTNAME):$(HTTP_PORT) \
		sitediff.yaml
sitediff_serve:
	sitediff serve

# Always sync files/DB
.PHONY: run run_mounted build build_no_cache devel stop ssh obliterate clean assets \
	assets/files backup
