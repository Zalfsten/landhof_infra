contents:
  repositories:
    - https://packages.wolfi.dev/os
    - '@local /work/build/packages'
  keyring:
    - https://packages.wolfi.dev/os/wolfi-signing.rsa.pub
  packages:
    - busybox
    - civicrm@local
    - supercronic@local

entrypoint:
  command: "/entrypoint.sh"

accounts:
  run-as: fpm
  users:
    - username: civicrm
      uid: ${CIVICRM_USER_ID}
      gid: ${CIVICRM_GROUP_ID}
      shell: /sbin/nologin
    - username: fpm
      uid: ${CIVICRM_FPM_USER_ID}
      gid: ${CIVICRM_GROUP_ID}
      shell: /sbin/nologin
  groups:
    - groupname: ${CIVICRM_GROUP_NAME}
      gid: ${CIVICRM_GROUP_ID}

paths:
  - path: /var/www/html
    type: permissions
    uid: ${CIVICRM_USER_ID}
    gid: ${CIVICRM_GROUP_ID}
    permissions: 0o0750
  - path: /run/php
    type: permissions
    uid: ${CIVICRM_USER_ID}
    gid: ${CIVICRM_GROUP_ID}
    permissions: 0o0770

work-dir: /var/www/html

# environment:
#   - CIVICRM_USER_ID=${CIVICRM_USER_ID}
#   - CIVICRM_GROUP_ID=${CIVICRM_GROUP_ID}

# apko unterstützt KEINE Variablen-Interpolation oder direkten Zugriff auf Umgebungsvariablen im YAML-File.
# Alle Werte müssen statisch im YAML stehen oder beim Build-Prozess (z.B. mit yq/envsubst) vorab ersetzt werden.

# Workaround:
# 1. Erzeuge das apko.yaml dynamisch aus einer Template-Datei (z.B. mit envsubst, yq, gomplate, etc.)
# 2. Beispiel mit envsubst:
#    cp civicrm.apko.yaml.template civicrm.apko.yaml
#    envsubst < civicrm.apko.yaml.template > civicrm.apko.yaml

# In civicrm.apko.yaml.template:
#   uid: ${CIVICRM_USER_ID}
#   gid: ${CIVICRM_GROUP_ID}

# Dann apko wie gewohnt ausführen.
