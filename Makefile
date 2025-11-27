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

# Finde alle apko Konfigurationen und definiere die entsprechenden .tar- und .lock.json-Ziele
IMAGES_DIR := $(BUILD_DIR)/images
APKO_CONFIGS := $(wildcard images/*.apko.yaml)
APKO_TARS := $(patsubst images/%.apko.yaml,$(IMAGES_DIR)/%.tar,$(APKO_CONFIGS))
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
	@echo "squid_version: $(SQUID_VERSION)" >> $@

$(KEY_PRIV) $(KEY_PUB): | $(BUILD_DIR)
	$(CONTAINER_RUNTIME) run --rm -v "$(PWD)":/work -w /work/build cgr.dev/chainguard/melange keygen
	$(CONTAINER_RUNTIME) run --rm -v "$(PWD)":/work alpine chown -R $(shell id -u):$(shell id -g) /work/$(KEY_PRIV) /work/$(KEY_PUB)

# --- Generische Paket / Stamp Definitionen ---------------------------------
# Liste aller lokal per melange zu bauenden Pakete (ein Verzeichnis unter packages/)
PACKAGES := aqbanking civicrm squid-config supercronic

# Kombinierte Regel-Template: definiert zuerst die <pkg>_STAMP Variable und
# erzeugt dann die konkrete Build-Regel für dieses Paket. Damit entfällt die
# vorherige separate foreach-Eval Schleife zur Stamp-Variablen-Erzeugung.
define GEN_PKG_RULE
$(1) := $(BUILD_DIR)/.$(1).stamp
$(BUILD_DIR)/.$(1).stamp: $(shell find packages/$(1) -type f) $(BUILD_VARS) $(KEY_PRIV) $(KEY_PUB) | $(BUILD_DIR)
	$(CONTAINER_RUNTIME) run --privileged --rm \
	  -v "$(PWD)":/work \
	  -w /work/$(BUILD_DIR) \
	  cgr.dev/chainguard/melange build \
	    --apk-cache-dir /work/apk_cache \
	    --arch $(ARCH) \
	    --vars-file $(BUILD_VARS_FILE) \
	    --signing-key melange.rsa \
	    --repository-append https://packages.wolfi.dev/os \
	    --keyring-append https://packages.wolfi.dev/os/wolfi-signing.rsa.pub \
	    ../packages/$(1)/.melange.yaml
	$(CONTAINER_RUNTIME) run --rm -v "$(PWD)":/work alpine chown -R $(shell id -u):$(shell id -g) /work/${BUILD_DIR}/packages
	@touch $$@
endef

# Evaluiere für jedes Paket eine konkrete Rule (inkl. Variable)
$(foreach p,$(PACKAGES),$(eval $(call GEN_PKG_RULE,$(p))))

define APKO_BUILD
	$(CONTAINER_RUNTIME) run --rm \
	  -v "$(PWD)":/work \
	  -w /work \
	  cgr.dev/chainguard/apko build --arch $(ARCH) \
	    --cache-dir /work/apk_cache \
	    --repository-append $(BUILD_DIR)/packages \
	    --sbom-path $(BUILD_DIR) \
	    --keyring-append $(KEY_PUB) \
	    $< $(notdir $1):$(2) $@
	$(CONTAINER_RUNTIME) run --rm -v "$(PWD)":/work alpine chown -R $(shell id -u):$(shell id -g) /work/$(IMAGES_DIR)
endef

$(IMAGES_DIR):
	mkdir -p $@

$(IMAGES_DIR)/civicrm-init.tar: images/civicrm-init.apko.yaml $(civicrm) | $(IMAGES_DIR)
	$(call APKO_BUILD,civicrm-init,$(CIVICRM_VERSION))

$(IMAGES_DIR)/civicrm-php-fpm.tar: images/civicrm-php-fpm.apko.yaml $(civicrm) | $(IMAGES_DIR)
	$(call APKO_BUILD,civicrm-php-fpm,$(CIVICRM_VERSION))

$(IMAGES_DIR)/civicrm-supercronic.tar: images/civicrm-supercronic.apko.yaml $(civicrm) $(supercronic) | $(IMAGES_DIR)
	$(call APKO_BUILD,civicrm-supercronic,$(CIVICRM_VERSION))

$(IMAGES_DIR)/squid.tar: images/squid.apko.yaml $(squid-config) | $(IMAGES_DIR)
	$(call APKO_BUILD,squid,$(SQUID_VERSION))

# Generische Build-Regel für alle apko-Images.
# Diese Regel verwendet die oben definierten _DEPS-Variablen, um die korrekten APK-Abhängigkeiten zu ermitteln.
# $(IMAGES_DIR)/%.tar: images/%.apko.yaml $(KEY_PUB) $(call stamps_from_deps,$($(notdir $*)_DEPS)) | $(IMAGES_DIR)
# 	@echo "Building image for '$*' with dependencies: images/%.apko.yaml $(KEY_PUB) $(call stamps_from_deps,$($(notdir $*)_DEPS))"
# 	$(CONTAINER_RUNTIME) run --rm \
# 	  -v "$(PWD)":/work \
# 	  -w /work \
# 	  cgr.dev/chainguard/apko build --arch $(ARCH) \
# 	    --cache-dir /work/apk_cache \
# 	    --repository-append $(BUILD_DIR)/packages \
# 	    --sbom-path $(BUILD_DIR) \
# 	    --keyring-append $(KEY_PUB) \
# 	    $< $(notdir $*):$(CIVICRM_VERSION) $@
# 	$(CONTAINER_RUNTIME) run --rm -v "$(PWD)":/work alpine chown -R $(shell id -u):$(shell id -g) /work/$(IMAGES_DIR)

# # Generische Regel zum Erstellen von apko lock files
# images/%.apko.lock.json: images/%.apko.yaml $(ALL_APKS)
# 	$(CONTAINER_RUNTIME) run --rm -v "$(PWD)":/work -w /work \
# 	  cgr.dev/chainguard/apko lock \
# 	  --arch $(ARCH) \
# 	  --keyring-append ${BUILD_DIR}/melange.rsa.pub \
# 	  $< --output $@
# 	$(CONTAINER_RUNTIME) run --rm -v "$(PWD)":/work alpine chown -R $(shell id -u):$(shell id -g) /work/$@

keygen: $(KEY_PRIV) $(KEY_PUB)

packages: $(PACKAGES)

apko: $(APKO_TARS)

images: $(APKO_TARS)
	@echo "Loading built images into $(CONTAINER_RUNTIME)"
	@for tar in $(APKO_TARS); do \
		$(CONTAINER_RUNTIME) load -i "$$tar"; \
	done

up: images
	sops exec-env .env.enc.yaml "${CONTAINER_RUNTIME} compose up -d"

clean:
	rm -rf $(BUILD_DIR)