# DevOps Home Lab (Docker Compose)

## Prereqs
- Docker Engine + Docker Compose v2
- OpenSSL + SSH client tools
- 16GB RAM minimum (Harbor + Grafana/Loki/Tempo is heavy)

## 1) Bootstrap secrets and SSH keys

### A) Create .env
cp .env.example .env
# Edit .env and replace all CHANGE_ME values.

### B) Generate SSH key for Ansible
mkdir -p ansible/keys
ssh-keygen -t ed25519 -f ansible/keys/id_ed25519 -N ""
cp ansible/keys/id_ed25519.pub ansible/keys/authorized_keys

### C) Generate Harbor private key (required)
openssl genrsa -out harbor/config/core/private_key.pem 4096

### D) Generate strong secrets
# Woodpecker agent secret (hex 64 chars)
openssl rand -hex 32

# Semaphore encryption key (base64)
head -c32 /dev/urandom | base64

## 2) Start everything
docker compose --env-file .env up -d --build

## 3) Verify Ansible connectivity (from the ansible-cli container)
docker compose exec -it ansible-cli bash
ansible -i ansible/hosts.ini all -m ping
ansible-playbook -i ansible/hosts.ini ansible/playbooks/10_check_disk_space.yml
ansible-playbook -i ansible/hosts.ini ansible/playbooks/20_install_nginx_on_workers.yml

## 4) Access UIs (host ports)
- Gitea:      http://localhost:3000
- Woodpecker: http://localhost:8000
- Grafana:    http://localhost:3001
- Semaphore:  http://localhost:3002
- Harbor:     http://localhost:8080
- Portainer:  http://localhost:9000 (or https://localhost:9443)
- Netdata:    http://localhost:19999

## 5) Configure Woodpecker with Gitea
1. In Gitea: Settings -> Applications -> OAuth2 -> Create new
2. Callback URL must be: http://localhost:8000/authorize
3. Put Client ID/Secret into .env as WOODPECKER_GITEA_CLIENT / WOODPECKER_GITEA_SECRET
4. Restart woodpecker:
   docker compose restart woodpecker-server woodpecker-agent

## 6) Configure Harbor Trivy scanning
Harbor uses scanners via "Interrogation Services / Scanners".
1. Login to Harbor (admin + your HARBOR_ADMIN_PASSWORD)
2. Add scanner:
   - Name: trivy
   - Endpoint: http://harbor-trivy:8080
   - Auth: none
3. Set it as default scanner for projects as desired.

## 7) Run Terragrunt demo
docker compose exec -it tf sh
cd /work/infra/live/dev
terragrunt run-all plan
terragrunt run-all apply

