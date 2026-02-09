# Architektur-Dokumentation  

**CiviCRM Single-Node Production Deployment (Docker Compose)**

## 1. Ziel & Rahmenbedingungen

Dieses Projekt betreibt **CiviCRM** auf einer **einzelnen Bare-Metal-Maschine** ohne Hochverfügbarkeitsanforderungen.  
Der Fokus liegt auf:

- Reproduzierbarkeit
- einfacher Wartbarkeit
- klarer Trennung von Build, Provisionierung und Betrieb
- minimaler operativer Komplexität

**Bewusste Entscheidungen:**

- Docker Compose wird auch in Produktion eingesetzt
- kein Kubernetes, kein Swarm
- kein Image-Build auf dem Produktivsystem
- keine CI-getriebenen Deployments

---

## 2. Überblick über die Architektur

### Komponenten

- **Build-Tooling**
  - apko
  - melange
- **Container Runtime**
  - Docker Engine
  - docker compose (Plugin)
- **Secrets Management**
  - sops
  - age
- **Provisionierung**
  - Ansible
- **Service Management**
  - systemd

---

## 3. Repository-Struktur (Single Repo)

Das Repository enthält **Build-, Deploy- und Ops-Code**, logisch getrennt durch Verzeichnisse:

```text
repo/
├─ build/                  # Image-Build (CI / lokal)
│  ├─ apko/
│  ├─ melange/
│  └─ Makefile
│
├─ deploy/                 # Laufzeit-Artefakte
│  ├─ docker-compose.yml
│  ├─ secrets.enc.yaml     # SOPS-verschlüsselt
│  ├─ config/
│  └─ systemd/
│     └─ civicrm.service
│
├─ ansible/                # Host-Provisionierung
│  ├─ inventory/
│  ├─ roles/
│  └─ playbook.yml
│
└─ docs/
   └─ architecture.md
