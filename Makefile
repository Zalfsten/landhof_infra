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
ALL_APKS := $(CIVICRM_APK) $(SUPERCRONIC_APK)
# APKO_FILE := config/civicrm.apko.yaml
# APKO_TAR := $(BUILD_DIR)/civicrm.tar

# Finde alle apko Konfigurationen und definiere die entsprechenden .tar- und .lock.json-Ziele
APKO_CONFIGS := $(wildcard images/*.apko.yaml)
APKO_TARS := $(patsubst images/%.apko.yaml,$(BUILD_DIR)/%.tar,$(APKO_CONFIGS))
APKO_LOCKS := $(patsubst images/%.apko.yaml,images/%.apko.lock.json,$(APKO_CONFIGS))

# Detect container runtime (docker or podman)
CONTAINER_RUNTIME := $(shell command -v podman >/dev/null 2>&1 && echo podman || echo docker)

.PHONY: all clean keygen packages civicrm supercronic apko images up lock

all: up

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(BUILD_VARS): .env | $(BUILD_DIR)
	@echo "civicrm_version: $(CIVICRM_VERSION)" > $@
	@echo "civicrm_cv_version: $(CIVICRM_CV_VERSION)" >> $@
	@echo "civicrm_php_version: $(CIVICRM_PHP_VERSION)" >> $@
	@echo "supercronic_version: $(SUPERCRONIC_VERSION)" >> $@

$(KEY_PRIV) $(KEY_PUB): | $(BUILD_DIR)
	$(CONTAINER_RUNTIME) run --rm -v "$(PWD)":/work -w /work/build cgr.dev/chainguard/melange keygen
	$(CONTAINER_RUNTIME) run --rm -v "$(PWD)":/work alpine chown -R $(shell id -u):$(shell id -g) /work/$(KEY_PRIV) /work/$(KEY_PUB)

# Definiere ein Template für den Melange-Build-Befehl
define MELANGE_BUILD
	$(CONTAINER_RUNTIME) run --privileged --rm -v "$(PWD)":/work -w /work/$(BUILD_DIR) \
	  cgr.dev/chainguard/melange build \
	    --arch $(ARCH) \
	    --vars-file $(BUILD_VARS_FILE) \
	    --signing-key melange.rsa \
	    --repository-append https://packages.wolfi.dev/os \
	    --keyring-append https://packages.wolfi.dev/os/wolfi-signing.rsa.pub \
	    ../packages/$(1)/.melange.yaml
	$(CONTAINER_RUNTIME) run --rm -v "$(PWD)":/work alpine chown -R $(shell id -u):$(shell id -g) /work/${BUILD_DIR}/packages
endef

# Alle Dateien aus den Paket-Verzeichnissen
CIVICRM_SRC := $(shell find packages/civicrm -type f)
SUPERCRONIC_SRC := $(shell find packages/supercronic -type f)

$(CIVICRM_APK): $(CIVICRM_SRC) $(BUILD_VARS) $(KEY_PRIV) $(KEY_PUB) | $(BUILD_DIR)
	$(call MELANGE_BUILD,civicrm)

$(SUPERCRONIC_APK): $(SUPERCRONIC_SRC) $(BUILD_VARS) $(KEY_PRIV) $(KEY_PUB) | $(BUILD_DIR)
	$(call MELANGE_BUILD,supercronic)

# Generische Build-Regel für alle apko-Images
$(BUILD_DIR)/%.tar: images/%.apko.yaml images/%.apko.lock.json $(ALL_APKS)
	$(CONTAINER_RUNTIME) run --rm -v "$(PWD)":/work -w /work \
	  cgr.dev/chainguard/apko build --arch $(ARCH) \
	  --sbom-path $(BUILD_DIR) \
	  --lockfile images/$*.apko.lock.json \
	  --keyring-append ${BUILD_DIR}/melange.rsa.pub \
	  $< $@:$(CIVICRM_VERSION) $@
	$(CONTAINER_RUNTIME) run --rm -v "$(PWD)":/work alpine chown -R $(shell id -u):$(shell id -g) /work/$(BUILD_DIR)

# Generische Regel zum Erstellen von apko lock files
images/%.apko.lock.json: images/%.apko.yaml $(ALL_APKS)
	$(CONTAINER_RUNTIME) run --rm -v "$(PWD)":/work -w /work \
	  cgr.dev/chainguard/apko lock \
	  --arch $(ARCH) \
	  --keyring-append ${BUILD_DIR}/melange.rsa.pub \
	  $< --output $@
	$(CONTAINER_RUNTIME) run --rm -v "$(PWD)":/work alpine chown -R $(shell id -u):$(shell id -g) /work/$@

keygen: $(KEY_PRIV) $(KEY_PUB)

packages: civicrm supercronic

civicrm: $(CIVICRM_APK)

supercronic: $(SUPERCRONIC_APK)

images: $(APKO_TARS)

lock: $(APKO_LOCKS)

apko: images

image: images
	$(foreach tar,$(APKO_TARS),${CONTAINER_RUNTIME} load -i $(tar);)

up: image
	sops exec-env .env.enc.yaml "${CONTAINER_RUNTIME} compose up -d"

clean:
	rm -rf $(BUILD_DIR)

