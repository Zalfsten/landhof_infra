ifneq ("$(wildcard .env)","")
	include .env
	export
endif

ARCH := $(shell uname -m)
BUILD_DIR := build
PKG_DIR := $(BUILD_DIR)/packages/$(ARCH)

BUILD_VARS_FILE := build.vars.yaml
BUILD_VARS := $(BUILD_DIR)/$(BUILD_VARS_FILE)
KEY_PRIV := $(BUILD_DIR)/melange.rsa
KEY_PUB := $(BUILD_DIR)/melange.rsa.pub
CIVICRM_APK := $(PKG_DIR)/civicrm-$(CIVICRM_VERSION)-r0.apk
SUPERCRONIC_APK := $(PKG_DIR)/supercronic-$(SUPERCRONIC_VERSION)-r0.apk
APKO_FILE := civicrm.apko.yaml
APKO_TAR := $(BUILD_DIR)/civicrm.tar
# APKO_LOCK := civicrm.apko.lock.json

.PHONY: all clean keygen civicrm supercronic apko image up

all: up

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(BUILD_VARS): .env | $(BUILD_DIR)
	@echo "civicrm_version: $(CIVICRM_VERSION)" > $@
	@echo "civicrm_cv_version: $(CIVICRM_CV_VERSION)" >> $@
	@echo "civicrm_php_version: $(CIVICRM_PHP_VERSION)" >> $@
	@echo "supercronic_version: $(SUPERCRONIC_VERSION)" >> $@

$(KEY_PRIV) $(KEY_PUB): | $(BUILD_DIR)
	docker run --rm -v "$(PWD)":/work -w /work/build cgr.dev/chainguard/melange keygen
	docker run --rm -v "$(PWD)":/work alpine chown -R $(shell id -u):$(shell id -g) /work/$(KEY_PRIV) /work/$(KEY_PUB)

$(CIVICRM_APK): entrypoint.sh civicrm.melange.yaml civicrm-php.ini civicrm-php-fpm.conf $(BUILD_VARS) $(KEY_PRIV) $(KEY_PUB) | $(BUILD_DIR)
	docker run --rm -v "$(PWD)":/work -w /work/$(BUILD_DIR) \
	  -v /var/run/docker.sock:/var/run/docker.sock \
	  -v /tmp:/tmp \
	  cgr.dev/chainguard/melange build \
	    --arch $(ARCH) \
	    --vars-file $(BUILD_VARS_FILE) \
	    --runner=docker \
	    --signing-key melange.rsa \
	    --repository-append https://packages.wolfi.dev/os \
	    --keyring-append https://packages.wolfi.dev/os/wolfi-signing.rsa.pub \
	    ../civicrm.melange.yaml
	docker run --rm -v "$(PWD)":/work alpine chown -R $(shell id -u):$(shell id -g) /work/${BUILD_DIR}/packages

$(SUPERCRONIC_APK): supercronic.melange.yaml $(BUILD_VARS) $(KEY_PRIV) $(KEY_PUB) | $(BUILD_DIR)
	docker run --rm -v "$(PWD)":/work -w /work/${BUILD_DIR} \
	  -v /var/run/docker.sock:/var/run/docker.sock \
	  -v /tmp:/tmp \
	  cgr.dev/chainguard/melange build \
	    --arch $(ARCH) \
	    --vars-file $(BUILD_VARS_FILE) \
	    --runner=docker \
	    --signing-key melange.rsa \
	    --repository-append https://packages.wolfi.dev/os \
	    --keyring-append https://packages.wolfi.dev/os/wolfi-signing.rsa.pub \
	    ../supercronic.melange.yaml
	docker run --rm -v "$(PWD)":/work alpine chown -R $(shell id -u):$(shell id -g) /work/${BUILD_DIR}/packages

# Note: A package lock file that is checked into git is a good thing for reproducible builds.
# The issue is: it depends on the apko file, which is a build artifact itself.
# So in our current approach the lock file can only be a build artifact as well -- which is good for nothing.

# $(APKO_LOCK): $(APKO_FILE) $(CIVICRM_APK) $(SUPERCRONIC_APK)
# 	docker run --rm -v "$(PWD)":/work -w /work \
# 	  cgr.dev/chainguard/apko lock \
# 	  --arch $(ARCH) \
# 	  --keyring-append ${BUILD_DIR}/melange.rsa.pub \
# 	  $(APKO_FILE) --output $(APKO_LOCK)
#   docker run --rm -v "$(PWD)":/work alpine chown -R $(shell id -u):$(shell id -g) /work/${BUILD_DIR}

#$(APKO_TAR): $(APKO_FILE) $(APKO_LOCK) $(CIVICRM_APK) $(SUPERCRONIC_APK)
# $(APKO_TAR): $(APKO_FILE) $(CIVICRM_APK) $(SUPERCRONIC_APK)
# 	docker run --rm -v "$(PWD)":/work -w /work -v /var/run/docker.sock:/var/run/docker.sock \
# 	  cgr.dev/chainguard/apko build --arch $(ARCH) \
# 	  --sbom-path $(BUILD_DIR) \
# 	  --lockfile $(APKO_LOCK) \
# 	  --keyring-append ${BUILD_DIR}/melange.rsa.pub \
# 	  $(APKO_FILE) civicrm:$(CIVICRM_VERSION) $(APKO_TAR)
$(APKO_TAR): $(APKO_FILE) $(CIVICRM_APK) $(SUPERCRONIC_APK)
	docker run --rm -v "$(PWD)":/work -w /work -v /var/run/docker.sock:/var/run/docker.sock \
	  cgr.dev/chainguard/apko build --arch $(ARCH) \
	  --sbom-path $(BUILD_DIR) \
	  --keyring-append ${BUILD_DIR}/melange.rsa.pub \
	  $(APKO_FILE) civicrm:$(CIVICRM_VERSION) $(APKO_TAR)

keygen: $(KEY_PRIV) $(KEY_PUB)

civicrm: $(CIVICRM_APK)

supercronic: $(SUPERCRONIC_APK)

apko: $(APKO_TAR)

image: $(APKO_TAR)
	docker load -i $(APKO_TAR)

up: image
	sops exec-env .env.enc.yaml 'docker compose up -d'

clean:
	rm -rf $(BUILD_DIR)

