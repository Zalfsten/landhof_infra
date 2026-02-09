ifneq ("$(wildcard deploy/.env)","")
	include deploy/.env
	export
endif

ARCH := $(shell uname -m)
ARCH_ALT := $(shell dpkg --print-architecture)
BUILD_DIR := dist
PKG_DIR := $(BUILD_DIR)/packages/$(ARCH)

BUILD_VARS_FILE := build.vars.yaml
BUILD_VARS := $(BUILD_DIR)/$(BUILD_VARS_FILE)
KEY_PRIV := $(BUILD_DIR)/melange.rsa
KEY_PUB := $(BUILD_DIR)/melange.rsa.pub

# Finde alle apko Konfigurationen und definiere die entsprechenden .tar- und .lock.json-Ziele
IMAGES_DIR := $(BUILD_DIR)/images
APKO_CONFIGS := $(wildcard build/images/*.apko.yaml)
APKO_TARS := $(patsubst build/images/%.apko.yaml,$(IMAGES_DIR)/%.tar,$(APKO_CONFIGS))
APKO_LOCKS := $(patsubst build/images/%.apko.yaml,build/images/%.apko.lock.json,$(APKO_CONFIGS))

# Detect container runtime (docker or podman)
CONTAINER_RUNTIME := $(shell command -v podman >/dev/null 2>&1 && echo podman || echo docker)

# Detect host directory for docker-in-docker mounts (when running in devcontainer)
HOST_DIR := $(shell $(CONTAINER_RUNTIME) inspect $(shell hostname) --format '{{range .Mounts}}{{if eq .Destination "$(PWD)"}}{{.Source}}{{end}}{{end}}' 2>/dev/null)
ifeq ($(HOST_DIR),)
    HOST_DIR := $(PWD)
endif

.PHONY: all clean keygen packages civicrm supercronic apko images up lock

all: up

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(BUILD_VARS): deploy/.env | $(BUILD_DIR)
	@echo "civicrm_version: $(CIVICRM_VERSION)" > $@
	@echo "civicrm_cv_version: $(CIVICRM_CV_VERSION)" >> $@
	@echo "civicrm_php_version: $(CIVICRM_PHP_VERSION)" >> $@
	@echo "civicrm_banking_version: $(CIVICRM_BANKING_VERSION)" >> $@
	@echo "supercronic_version: $(SUPERCRONIC_VERSION)" >> $@
	@echo "squid_version: $(SQUID_VERSION)" >> $@

$(KEY_PRIV) $(KEY_PUB): | $(BUILD_DIR)
	$(CONTAINER_RUNTIME) run --rm -v "$(HOST_DIR)":/work -w /work/dist cgr.dev/chainguard/melange keygen
	$(CONTAINER_RUNTIME) run --rm -v "$(HOST_DIR)":/work alpine chown -R $(shell id -u):$(shell id -g) /work/$(KEY_PRIV) /work/$(KEY_PUB)

# --- Generische Paket / Stamp Definitionen ---------------------------------
# Liste aller lokal per melange zu bauenden Pakete (ein Verzeichnis unter build/packages/)
PACKAGES := aqbanking civicrm squid-config supercronic
PACKAGES_STAMPS := $(foreach p,$(PACKAGES),$($(p)))

# Kombinierte Regel-Template: definiert zuerst die <pkg>_STAMP Variable und
# erzeugt dann die konkrete Build-Regel für dieses Paket. Damit entfällt die
# vorherige separate foreach-Eval Schleife zur Stamp-Variablen-Erzeugung.
define GEN_PKG_RULE
$(1) := $(BUILD_DIR)/.$(1).stamp
$(BUILD_DIR)/.$(1).stamp: $(shell find build/packages/$(1) -type f) $(BUILD_VARS) $(KEY_PRIV) $(KEY_PUB) | $(BUILD_DIR)
	$(CONTAINER_RUNTIME) run --privileged --rm \
	  -v "$(HOST_DIR)":/work \
	  -w /work/$(BUILD_DIR) \
	  cgr.dev/chainguard/melange build \
	    --apk-cache-dir /work/apk_cache \
	    --arch $(ARCH) \
	    --vars-file $(BUILD_VARS_FILE) \
	    --signing-key melange.rsa \
	    --repository-append https://packages.wolfi.dev/os \
	    --keyring-append https://packages.wolfi.dev/os/wolfi-signing.rsa.pub \
	    ../build/packages/$(1)/.melange.yaml
	$(CONTAINER_RUNTIME) run --rm -v "$(HOST_DIR)":/work alpine chown -R $(shell id -u):$(shell id -g) /work/${BUILD_DIR}/packages
	@touch $$@
endef

# Evaluiere für jedes Paket eine konkrete Rule (inkl. Variable)
$(foreach p,$(PACKAGES),$(eval $(call GEN_PKG_RULE,$(p))))

define APKO_BUILD
	$(CONTAINER_RUNTIME) run --rm \
	  -v "$(HOST_DIR)":/work \
	  -w /work \
	  cgr.dev/chainguard/apko build --arch $(ARCH) \
	    --cache-dir /work/apk_cache \
	    --repository-append $(BUILD_DIR)/packages \
	    --sbom-path $(BUILD_DIR) \
	    --keyring-append $(KEY_PUB) \
	    $< $(notdir $1):$(2) $@
	$(CONTAINER_RUNTIME) run --rm -v "$(HOST_DIR)":/work alpine chown -R $(shell id -u):$(shell id -g) /work/$(IMAGES_DIR)
endef

$(IMAGES_DIR):
	mkdir -p $@

$(IMAGES_DIR)/civicrm-init.tar: build/images/civicrm-init.apko.yaml $(civicrm) $(KEY_PUB) | $(IMAGES_DIR)
	$(call APKO_BUILD,civicrm-init,$(CIVICRM_VERSION))

$(IMAGES_DIR)/civicrm-php-fpm.tar: build/images/civicrm-php-fpm.apko.yaml $(civicrm) $(KEY_PUB) | $(IMAGES_DIR)
	$(call APKO_BUILD,civicrm-php-fpm,$(CIVICRM_VERSION))

$(IMAGES_DIR)/civicrm-supercronic.tar: build/images/civicrm-supercronic.apko.yaml $(civicrm) $(supercronic) $(KEY_PUB) | $(IMAGES_DIR)
	$(call APKO_BUILD,civicrm-supercronic,$(CIVICRM_VERSION))

$(IMAGES_DIR)/civicrm-aqbanking.tar: build/images/civicrm-aqbanking.apko.yaml $(civicrm) $(aqbanking) $(KEY_PUB) | $(IMAGES_DIR)
	$(call APKO_BUILD,civicrm-aqbanking,$(CIVICRM_VERSION))

$(IMAGES_DIR)/squid.tar: build/images/squid.apko.yaml $(squid-config) $(KEY_PUB) | $(IMAGES_DIR)
	$(call APKO_BUILD,squid,$(SQUID_VERSION))

keygen: $(KEY_PRIV) $(KEY_PUB)

packages: $(PACKAGES_STAMPS)

apko: $(APKO_TARS)

images: $(APKO_TARS)
	@echo "Loading built images into $(CONTAINER_RUNTIME)"
	@for tar in $(APKO_TARS); do \
		output=$$($(CONTAINER_RUNTIME) load -i "$$tar"); \
		full_tag=$$(echo "$$output" | awk -F': ' '{print $$2}'); \
		base_tag=$$(echo $$full_tag | sed "s/-$(ARCH_ALT)//"); \
		$(CONTAINER_RUNTIME) tag $$full_tag $$base_tag; \
	done

up: images
	sops exec-env deploy/.env.enc.yaml "$(CONTAINER_RUNTIME) compose -f deploy/docker-compose.yaml --env-file deploy/.env up -d"

clean:
	rm -rf $(BUILD_DIR)