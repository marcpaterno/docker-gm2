# Makefile to run docker stuff
#  This is a generic Makefile to run our different images
#


.PHONY: help bkg x11 shell

NEW_DOCKER_MACHINE_NAME ?= default

LOCAL_VOLUME ?= $(HOME)
NAME ?= aContainer
DOCKER_HISTORY_FILE ?= $(PWD)/docker_bash_history_$(NAME)
BUILD_ARGS ?=
EXTRA_DOCKER_RUN_FLAGS ?=
EXTRA_RUN_INSTRUCTIONS ?=
VOL ?= /home/gm2/$(NAME)
VOLS_FROM ?=

ARGS_RM ?=
ARGS_BKG ?=
ARGS_DISPLAY ?=
ARGS_PRIVILEGED ?=

GRAFANA_DIR ?= $(PWD)/runtime/grafana

# Deal with differences in the docker-machine (virtualbox vs xhyve)
ifdef DOCKER_MACHINE_NAME
DM_DRIVER := $(shell docker-machine inspect --format='{{.DriverName}}' ${DOCKER_MACHINE_NAME})
NETWORK_INTERFACE := unknown
ifeq ($(DM_DRIVER),xhyve)
NETWORK_INTERFACE := bridge100
else ifeq ($(DM_DRIVER),virtualbox)
NETWORK_INTERFACE := vboxnet0
endif
endif

# Deal with VOL and VOLS_FROM
ifdef VOL
EXTRA_DOCKER_RUN_FLAGS += -v $(VOL)
endif

# VOLS_FROM can be a space separeated list like VOLS_FROM="abc def"
ifdef VOLS_FROM
EXTRA_DOCKER_RUN_FLAGS += $(foreach vf,$(VOLS_FROM),--volumes-from $(vf))
endif

# ----------------------

help-top:
	@echo 'Host commands:'
	@echo ' '
	@echo ' OSX/Windows: You may need to run '
	@echo '       eval $$(docker-machine env <VM-name>)'
	@echo '  to connect to your docker VM'
	@echo ' '
	@echo 'HIGHER ORDER FUNCTIONS:'
	@echo ' '
	@echo ' make cvmfs-server   -- Start the CVMFS server to supply cvmfs to other clients'
	@echo ' make dev-shell      -- Make a development shell container that gets CVMFS, X11'
	@echo ' make allinea-shell  -- Make a development shell container that gets CVMFS, X11 and Allinea'
	@echo ' make igprof-shell   -- Make a development shell container that gets CVMFS, X11 and Igprof'
	@echo ' make plain-shell    -- Make a shell container without CVMFS, but with X11'
	@echo ' make clean          -- Stop and remove the most recently started container'
	@echo ' '
	@echo ' make ARCHIVE=container archive -- Archive volumes and log from a container to a tar file'
	@echo ' '
	@echo 'IMPORTANT OPTIONS:'
	@echo ' '
	@echo ' NAME=<container name>'
	@echo ' VOL=<full path within container to directory accessible to other containers>'
	@echo ' VOLS_FROM=<container(s) from which to obtain volumes>'
	@echo ' '
	@echo 'EXAMPLES:'
	@echo '  make NAME=my-analysis VOL=/home/gm2/ana-v1 dev-shell'
	@echo '  make NAME=my-other-analysis VOL=/home/gm2/ana-v1.1 igprof-shell'
	@echo '  make NAME=study VOLS_FROM="my-analysis my-other-analysis" plain-shell'
	@echo ' '
	@echo 'Do "make help-basic" to see other more basic functionality'
	@echo 'Do "make help-machines" to see docker-machine releated functionality'
	@echo 'Do "make help-monitoring" to see monitoring related functionality'

help-basic :
	@echo 'BASIC FUNCTIONS:'
	@echo ' make build  -- build the image in the current directory to name IMAGE'
	@echo ' make shell  -- Run container with shell (if image supports it)'
	@echo '                with LOCAL_VOLUME and BASH_HISTORY_FILE'
	@echo ' make clean  -- Stop and remove the most recently started container'
	@echo ' '
	@echo ' make build-all -- Build all of the images (must be run from docker-gm2 top level dir)'
	@echo ' '
	@echo '   Options in front of shell...'
	@echo '     These can be combined like "make x11 rm shell"'
	@echo '      make x11 shell   -- run with X11'
	@echo '      make bkg shell   -- run in background'
	@echo '      make rm  shell   -- Run and remove container when done'

help-machines:
	@echo ' make create-machine-xhyve      -- Build an xhyve VM on OSX (see https://goo.gl/q4WTCd )'
	@echo ' make create-machine-vbox       -- Create a virtualbox VM on OSX'
	@echo ' make create-machine-vbox-vdi   -- Create a virtualbox VM on OSX but with a VDI disk (shrinkable)'
	@echo ' make shrink-disk-vbox          -- Shrink the VDI disk on the virtualbox VM'
	@echo ' make fix-clock-skew-xhyve      -- Resync the clock on the xhyve VM - fixes clock skew errors'
	@echo ' '
	@echo 'Set NEW_DOCKER_MACHINE_NAME accordingly. Default is "default"'


# ---- Internal Targets ----
check-image-is-set:
	@if [ -z $(IMAGE) ] ; then \
		echo 'IMAGE is not set'; \
		exit 1 ; \
	fi

do-build: check-image-is-set
	docker build $(BUILD_ARGS) -t $(IMAGE) .

do-bash-history:
	# We need to create the history file, else docker run makes it a directory
	touch $(DOCKER_HISTORY_FILE)

do-bkg:
	$(eval DID_BKG := yes)
	$(eval ARGS_BKG := -d )
	$(eval ARGS_RM := )

do-rm:
	$(eval ARGS_RM := --rm )

do-x11:
	$(eval DID_X11 := yes)
	$(eval MYHOSTIP := $(shell ifconfig $(NETWORK_INTERFACE)  | grep inet | cut -d' ' -f 2))
	$(eval ARGS_DISPLAY := -e DISPLAY=$(MYHOSTIP):0)
	$(eval DOCKER_VM_IP := $(shell docker-machine ip $(DOCKER_MACHINE_NAME) ))
	-killall socat
	open -a Xquartz
	socat TCP-LISTEN:6000,reuseaddr,fork,range=$(DOCKER_VM_IP):255.255.255.0 UNIX-CLIENT:\"$$DISPLAY\" &
	# Must set the range option, else our port 6000 is open to everybody!

do-docker-run: check-image-is-set
	# Run the container
	-docker run $(ARGS_RM) $(ARGS_BKG) -ti \
	  --name=$(NAME) \
		$(ARGS_DISPLAY) $(ARGS_PRIVILEGED) \
		-v $(DOCKER_HISTORY_FILE):/home/gm2/.bash_history \
		-v $(LOCAL_VOLUME):$(LOCAL_VOLUME) \
		$(EXTRA_DOCKER_RUN_FLAGS) \
		$(IMAGE) \
		$(CMD)
	@echo $(EXTRA_DOCKER_RUN_INSTRUCTIONS)

do-post-run:
	@if [ -n "$(DID_BKG)" ] ; then \
		echo 'When you finish with your container, run "make clean"'; \
	else \
		if [ -n "$(DID_X11)" ] ; then \
			echo 'Killing socat'; \
			killall socat; \
		fi \
	fi

do-clean-recent-container:
	docker stop -t 0 `docker ps -lq`
	docker rm `docker ps -lq`

do-kill-socat:
	-killall socat

# ----- External Targets -----

help: help-top

build: do-build

x11: do-x11

bkg: do-bkg

rm : do-rm

shell: | do-bash-history do-docker-run do-post-run

clean: | do-clean-recent-container do-kill-socat

# ---- Higher order functionality

cvmfs-server:
	$(MAKE) -C c67CvmfsNfsServer cvmfs bkg shell

dev-shell:
	$(MAKE) -C c67CvmfsNfsClient x11 shell

single-analysis-shell:
	$(MAKE) -C c67CvmfsNfsClient EXTRA_DOCKER_RUN_FLAGS="--memory=1g" x11 shell

plain-shell:
	$(MAKE) -C c67Base x11 shell

allinea-shell:
	$(MAKE) -C c67Allinea allinea x11 shell

igprof-shell:
	$(MAKE) -C c67Igprof x11 shell

ps:
	@docker ps -sa --format "table {{.Names}}\t{{.ID}}\t{{.Status}}\t{{.RunningFor}} ago\t{{.Image}}\t{{.Labels}}"

# ---- Making machines

# Build all of the images
build-all:
	$(MAKE) -C c67Base build
	$(MAKE) -C c67Cvmfs build
	$(MAKE) -C c67CvmfsNfsServer build
	$(MAKE) -C c67CvmfsNfsClient build
	$(MAKE) -C c67Allinea build
	$(MAKE) -C c67Igprof build
	$(MAKE) -C c67Spack build

# Create the Xhyve VM (for OSX with xhyve installed)
create-machine-xhyve :
	docker-machine create --driver xhyve \
		--xhyve-experimental-nfs-share \
		--xhyve-cpu-count=8 \
		--xhyve-memory-size=8192 \
		$(NEW_DOCKER_MACHINE_NAME)

# Create the virtualbox machinecreate-machine-vbox :
create-machine-vbox :
	docker-machine create --driver virtualbox \
	 	--virtualbox-cpu-count=4 \
		--virtualbox-memory=8192 \
		--virtualbox-dns-proxy \
		--virtualbox-host-dns-resolver \
		$(NEW_DOCKER_MACHINE_NAME)

# Create the virtualbox machine
create-machine-vbox-vdi : create-machine-vbox
	# We're going to make some adjustments to the VM, so power down
	docker-machine stop "$(NEW_DOCKER_MACHINE_NAME)"
	# Do not stop the VM on low battery warning
	VBoxManage setextradata "$(NEW_DOCKER_MACHINE_NAME)" "VBoxInternal2/SavestateOnBatteryLow" 0
	# Convert the vmdk disk to vdi so we can shrink it later
	# Note - since cd happens in a subshell, we need to && things
	cd $$(docker-machine inspect --format '{{.HostOptions.AuthOptions.StorePath}}' $(NEW_DOCKER_MACHINE_NAME)) && VBoxManage clonehd --format vdi disk.vmdk disk.vdi
	# Remove and delete the vmdk disk
	VBoxManage storageattach "$(NEW_DOCKER_MACHINE_NAME)" --storagectl SATA --port 1 --medium none
	VBoxManage closemedium $$(docker-machine inspect --format '{{.HostOptions.AuthOptions.StorePath}}' $(NEW_DOCKER_MACHINE_NAME))/disk.vmdk --delete
	# Add the vdi disk to the VM
	VBoxManage storageattach "$(NEW_DOCKER_MACHINE_NAME)" --storagectl SATA --port 1 --type hdd --nonrotational on \
	           --medium $$(docker-machine inspect --format '{{.HostOptions.AuthOptions.StorePath}}' $(NEW_DOCKER_MACHINE_NAME))/disk.vdi
	# Restart the VM
	docker-machine start "$(NEW_DOCKER_MACHINE_NAME)"
	# Apparently we need to recreate the certificates
	docker-machine regenerate-certs -f "$(NEW_DOCKER_MACHINE_NAME)"
	docker-machine env "$(NEW_DOCKER_MACHINE_NAME)"

# Shrink a virtualbox disk
shrink-disk-vbox:
	# Make a big empty file - may take a long time (it will end on an error)
	docker-machine ssh $(DOCKER_MACHINE_NAME) "cd /mnt/sda1 && sudo dd if=/dev/zero of=bigemptyfile bs=4096k || sudo rm -f bigemptyfile"
	docker-machine stop $(DOCKER_MACHINE_NAME)
	ls -lh $$(docker-machine inspect --format '{{.HostOptions.AuthOptions.StorePath}}' $(DOCKER_MACHINE_NAME))/disk.vdi
	VBoxManage modifyhd $$(docker-machine inspect --format '{{.HostOptions.AuthOptions.StorePath}}' $(DOCKER_MACHINE_NAME))/disk.vdi --compact
	ls -lh $$(docker-machine inspect --format '{{.HostOptions.AuthOptions.StorePath}}' $(DOCKER_MACHINE_NAME))/disk.vdi
	docker-machine start $(DOCKER_MACHINE_NAME)

# Fix clock-skew errors
fix-clock-skew-xhyve :
	docker-machine ssh $(DOCKER_MACHINE_NAME) "sudo date -u -D %s --set $(shell date -u +%s)"

# Monitoring
help-monitoring:
	@echo '  make monitoring         -- Turn on monitoring'
	@echo '  make monitoring-stop    -- Turn off monitoring'

monitoring:
	# InfluxDB stores the monitoring data
	docker run -d -p 8083:8083 -p 8086:8086 --expose 8090 --expose 8099 \
						 -e PRE_CREATE_DB=cadvisor \
						 --name influxsrv tutum/influxdb

	# Cadvisor collects the monitoring data
	docker run \
		--volume=/:/rootfs:ro \
		--volume=/var/run:/var/run:rw \
		--volume=/sys:/sys:ro \
		--volume=/var/lib/docker/:/var/lib/docker:ro \
		--publish=9090:8080 \
		--link=influxsrv:influxsrv  \
		--detach=true \
		--name=cadvisor \
		google/cadvisor \
		-storage_driver=influxdb \
		-storage_driver_db=cadvisor \
		-storage_driver_host=influxsrv:8086

	docker run -d -v /var/lib/grafana -v /Users:/Users --name grafana-storage busybox:latest cp $(PWD)/grafana/grafana.db /var/lib/grafana

	# Grafana displays the monitoring data
	docker run -d \
		-e HTTP_USER=admin \
		-e HTTP_PASS=admin \
		-e INFLUXDB_HOST=localhost \
		-e INFLUXDB_PORT=8086 \
		-e INFLUXDB_NAME=cadvisor \
		-e INFLUXDB_USER=root \
		-e INFLUXDB_PASS=root \
		--link=influxsrv:influxsrv  \
		--name=grafana \
		--volumes-from grafana-storage \
		-p 3000:3000 \
		grafana/grafana

	@echo Look at instananeous monitoring from CAdivsor on port 9090
	@echo Look at historical monitoring on port 3000

monitoring-stop:
	-docker stop influxsrv cadvisor grafana grafana-storage
	-docker rm influxsrv cadvisor grafana grafana-storage

monitoring-grafana-save-config:
	docker exec grafana cp /var/lib/grafana/grafana.db $(PWD)/grafana/grafana.db

check-archive-is-set:
	@if [ -z $(ARCHIVE) ] ; then \
		echo 'ARCHIVE is not set - set it to the name of the container to archive'; \
		exit 1 ; \
	fi

archive: check-archive-is-set
	@$(eval ARCHIVE_VOLS := /container/description /container/log)
	@$(eval ARCHIVE_VOLS += $(shell docker inspect --format '{{range .Mounts}}{{if eq .Driver "local" }}{{ .Destination }} {{end}}{{end}}' $(ARCHIVE) ))
	@docker logs -t $(ARCHIVE) > archive_log
	@echo $(ARCHIVE) > archive_description
	@echo "\nWrite Description Here\n\n" >> archive_description
	@docker inspect $(ARCHIVE) >> archive_description
	@$(EDITOR) archive_description
	@docker run --rm --volumes-from $(ARCHIVE) -v $(PWD):/backup \
	                -v $(PWD)/archive_description:/container/description \
									-v $(PWD)/archive_log:/container/log \
									c67base \
									tar cvzf /backup/$(ARCHIVE).tgz $(ARCHIVE_VOLS)
	@rm -f archive_log archive_description
	@echo WROTE TO $(ARCHIVE).tgz
