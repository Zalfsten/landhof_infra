# Project docs

## Install tools

Note: this part is obsolete/not needed as long as we're using the melange and apko docker images.

```bash
# Get latest release versions from GitHub API
MELANGE_VERSION=$(curl -s https://api.github.com/repos/chainguard-dev/melange/releases/latest | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')
APKO_VERSION=$(curl -s https://api.github.com/repos/chainguard-dev/apko/releases/latest | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')

# Detect architecture
ARCH=$(uname -m)
case $ARCH in
    x86_64) ARCH="amd64" ;;
    aarch64) ARCH="arm64" ;;
    *) echo "Unsupported architecture: $ARCH"; exit 1 ;;
esac

# Install bubblewrap (bwrap) for melange
sudo apt-get update && sudo apt-get install -y bubblewrap

# Configure user namespaces for bubblewrap (required in containers)
echo 'kernel.unprivileged_userns_clone=1' | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
# Alternative: enable for current session only
sudo sysctl kernel.unprivileged_userns_clone=1

# Download and install melange
echo "Installing melange $MELANGE_VERSION for $ARCH..."
curl -fsSL "https://github.com/chainguard-dev/melange/releases/download/$MELANGE_VERSION/melange_${MELANGE_VERSION#v}_linux_$ARCH.tar.gz" | sudo tar -xz -C /usr/local/bin --strip-components=1 melange_${MELANGE_VERSION#v}_linux_$ARCH/melange
sudo chmod +x /usr/local/bin/melange

# Download and install apko
echo "Installing apko $APKO_VERSION for $ARCH..."
curl -fsSL "https://github.com/chainguard-dev/apko/releases/download/$APKO_VERSION/apko_${APKO_VERSION#v}_linux_$ARCH.tar.gz" | sudo tar -xz -C /usr/local/bin --strip-components=1 apko_${APKO_VERSION#v}_linux_$ARCH/apko
sudo chmod +x /usr/local/bin/apko
```

## Build packages and image

Note: we need to use dockerized melange and apko tools as elevated privileges are requires that are not available
within a dev container. The downside is that melange needs root permissions and creates output files that belong
to root. So we need to change the ownership afterwards -- misusing docker to gain root permissions to do so.

```bash
# Create packages directory
mkdir -p packages

# Create a melange key (run in docker container)
docker run --rm -v "$(pwd)":/work -w /work/packages cgr.dev/chainguard/melange keygen

CIVICRM_VERSION="6.7.1"
cat > /workspaces/landhof_infra/build.vars.yaml <<EOF
civicrm_version: ${CIVICRM_VERSION}
civicrm_user_id: 900
civicrm_group_id: 900
php_version: 8.3
supercronic_version: 0.2.38
supercronic_user_id: 901
supercronic_group_id: 901
EOF

# Build civicrm package (run melange with docker to get root privileges)
docker run --rm \
  -v "$(pwd)":/work -w /work \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v /tmp:/tmp \
  cgr.dev/chainguard/melange build --arch host --runner=docker --signing-key packages/melange.rsa \
    --repository-append https://packages.wolfi.dev/os \
    --keyring-append https://packages.wolfi.dev/os/wolfi-signing.rsa.pub \
    --vars-file build.vars.yaml \
    civicrm.melange.yaml

# Build supercronic package
docker run --rm \
  -v "$(pwd)":/work -w /work \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v /tmp:/tmp \
  cgr.dev/chainguard/melange build --arch host --runner=docker --signing-key packages/melange.rsa \
    --repository-append https://packages.wolfi.dev/os \
    --keyring-append https://packages.wolfi.dev/os/wolfi-signing.rsa.pub \
    --vars-file build.vars.yaml \
    supercronic.melange.yaml

# Fix ownership of packages directory, in fact this is a workaround to gain root permissions
docker run --rm -v "$(pwd)":/work alpine chown -R $(id -u):$(id -g) /work/packages

# Build apko image
docker run --rm \
  -v "$(pwd)":/work -w /work \
  -v /var/run/docker.sock:/var/run/docker.sock \
  cgr.dev/chainguard/apko build --arch host --keyring-append packages/melange.rsa.pub \
    civicrm.apko.yaml civicrm:$CIVICRM_VERSION civicrm.tar
```

## Load image into Docker

```bash
docker load -i civicrm.tar
```

## run

```bash
sops exec-env .env.enc.yaml 'docker compose up'
```

## references

* <https://github.com/civicrm/civicrm-docker>
