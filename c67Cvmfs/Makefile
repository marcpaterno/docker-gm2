IMAGE ?= lyonfnal/c67cvmfs
NAME ?= c67cvmfs

ARGS_PRIVILEGED := --privileged

help-cvmfs:
	@echo "-----------"
	@echo "   Additonal option in front of shell from CVMFS"
	@echo "      make cvmfs shell   -- Run with persistent cvmfs cache"

do-cvmfs:
	$(eval DID_CVMFS := yes)
	$(eval EXTRA_DOCKER_RUN_FLAGS += --volumes-from cvmfs_cache)
	# Checking for cvmfs_cache data container
	@if ! docker ps -a | grep cvmfs_cache -q ; then \
		echo 'Creating cvmfs_cache data container';\
		docker create -v /var/cvmfs/cache --name cvmfs_cache $(IMAGE) /bin/true;\
	fi

cvmfs: do-cvmfs

help: help-top help-cvmfs

include ../Makefile
