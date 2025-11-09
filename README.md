# Project docs

## Install tools

Note: this part is obsolete/not needed as long as we're using the melange and apko docker images.

```bash
# Get latest release versions from GitHub API
MELANGE_VERSION=$(curl -s https://api.github.com/repos/chainguard-dev/melange/releases/latest | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')
APKO_VERSION=$(curl -s https://api.github.com/repos/chainguard-dev/apko/releases/latest | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')
SOPS_VERSION=$(curl -s https://api.github.com/repos/getsops/sops/releases/latest | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')

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

# Download and install sops
echo "Installing sops $SOPS_VERSION for $ARCH..."
sudo curl -fsSL "https://github.com/getsops/sops/releases/download/$SOPS_VERSION/sops-${SOPS_VERSION}.linux.$ARCH" -o /usr/local/bin/sops
sudo chmod +x /usr/local/bin/sops
```

### podman compose on Debian

To be more secure it's a good idea to use podman instead of docker. Install it like this Debian systems:

```bash
apt update && apt install podman docker-compose-plugin
# tell podman to use the docker compose plugin
mkdir -p ~/.config/containers
echo '[engine]
compose_providers = ["/usr/libexec/docker/cli-plugins/docker-compose"]
' > ~/.config/containers/containers.conf
```

This only works, if the podman daemon is running (which is not the case by default, because a plain podman
command doesn't need it). To start it as unprivileged user:

```bash
podman system service --time=0 &
```

It's also possible to create a systemd user service for this purpose:

```bash
mkdir -p ~/.config/systemd/user
echo '[Unit]
Description=Podman API Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/podman system service --time=0
Restart=on-failure

[Install]
WantedBy=default.target
' > ~/.config/systemd/user/podman.service
systemctl --user daemon-reload
systemctl --user enable podman.service
systemctl --user start podman.service
systemctl --user status podman.service
```

For productive use a system-wide systemd service will be necessary, that starts on system boot.

### using `setfacl`

We want to use a single nginx service for multiple app downstream. A common practice if nginx is also
use as web serve (not just as reverse proxy) is to mount a volume that is shared between nginx and
the app. Both -- the app and nginx -- need permissions to the files in this volume. This is typically
done with the help of a user group that is shared between nginx and the app. This works fine as long
as there is only one app, because the nginx container can be run with and arbitary group, e.g.
`www-data:12345`. When a second app with a second group comes into play, this is not possible any more,
as we can only specify a single group when running the container. A solution would be to use a single
group for all services inside the same compose file. This reduces security and flexibilty -- maybe we
would like to use group for another purpose. This is where `setfacl` comes into play.

With `setfacl` we can give specific user access permissions to `/var/www/html` although they do not
share a group. This can be done with the entrypoint scrip of the app, completely independent of nginx:

```bash
# Grant read permissions to user 101 (nginx)
setfacl -R -m u:101:rx /var/www/html
# Grant write permissions to user 101 (nginx)
setfacl -R -m u:101:rwx /var/www/html/uploads
setfacl -R -m u:101:rwx /var/www/html/cache
# Ensure all new file in the folder also gain write permissions by user 101 (nginx)
setfacl -R -d -m u:101:rwx /var/www/html/uploads
setfacl -R -d -m u:101:rwx /var/www/html/cache
```

Only the approach requires that the host volume that contains the container volumes is mounted with
the mount option `acl`. This is the case on current Debian and ubuntu systems, even if it's not so
easy to notice, beacse the `acl` mount option is part of the `default` mount option. To test, if your
volume support `acl`:

```bash
touch /tmp/testfile
setfacl -m u:nobody:r /tmp/testfile
getfacl /tmp/testfile
```

If user `nobody` is listed in the permissions, everything is fine.

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
