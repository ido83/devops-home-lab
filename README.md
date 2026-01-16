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


## Validation procedure for your current compose
### Run these commands from the lab root folder (where docker-compose.yaml and .env live):
# 1) Ensure .env is loaded and Compose can fully render the model
docker compose --env-file .env config > /tmp/compose.rendered.yaml

# 2) Fail-fast: verify no unresolved variables remain in the rendered compose
grep -n '\${' /tmp/compose.rendered.yaml || echo "OK: no unresolved variables"

# 3) Pull images one-by-one (best signal for 404 / tag errors)
docker compose --env-file .env pull --no-parallel

# 4) Start the stack
docker compose --env-file .env up -d --build

# 5) Check status
docker compose ps

# 6) If something fails, inspect the exact service logs:
# (replace <svc> with the failing service name, e.g. harbor-core, woodpecker-server)
docker compose logs -n 200 <svc>

# DevOps Home Lab (Docker Compose) – Master/Workers + ALM + Registry + Observability

This repository provides a Docker-based DevOps home lab designed to emulate a multi-node environment (Master + Workers) and a full DevOps toolchain:
- Node simulation: Ubuntu “servers” with SSH + Docker-in-Docker (dockerd)
- Automation: Ansible inventory + demo playbooks + roles, Semaphore UI, Terraform/Terragrunt toolbox
- ALM/CI: Gitea + Woodpecker CI
- Registry + scanning: Harbor + Trivy adapter (registered in Harbor)
- Management & Observability: Portainer, Netdata, Grafana + Loki + Tempo + Promtail

## Table of Contents
1. Architecture overview
2. Prerequisites and host sizing
3. Security and isolation model
4. Initial bootstrap (secrets, SSH keys, Harbor key)
5. Start/stop lifecycle
6. Access URLs
7. Ansible usage (playbooks, roles, adding workers)
8. Semaphore UI usage
9. Terraform/Terragrunt usage
10. Gitea usage
11. Harbor usage (push/pull, Trivy scanning)
12. Woodpecker CI/CD usage (pipeline + pushing to Harbor + optional deploy)
13. Observability usage (Loki logs, Tempo traces, Grafana dashboards)
14. Operational troubleshooting

---

## 1) Architecture Overview

All services run on a single custom Docker bridge network (example: `devops_lab`) so containers can resolve each other by service name.

High-level topology:

- Simulated nodes:
  - `lab-master` (SSH, Docker daemon inside)
  - `lab-worker1`, `lab-worker2` (SSH, Docker daemon inside)

- Automation:
  - `ansible-cli` (Ansible runner container with the repo mounted)
  - `tf` (Terraform/Terragrunt runner container with the repo mounted)
  - `semaphore` + `semaphore-db` (Semaphore UI)

- ALM/CI:
  - `gitea` + `gitea-db`
  - `woodpecker-server` + `woodpecker-agent`

- Registry:
  - Harbor stack (Harbor services + redis/db + nginx/proxy depending on your compose)
  - `harbor-trivy` scanner adapter (registered inside Harbor)

- Observability:
  - `grafana`, `loki`, `tempo`, `promtail`
  - `netdata`
  - `portainer`

---

## 2) Prerequisites and Host Sizing

### Required
- Docker Engine + Docker Compose v2
- 16GB RAM minimum for full stack (Harbor + LGT stack are memory heavy)
- 30–50GB free disk recommended for registry + logs + volumes

### Recommended
- Run this lab inside a VM or on a dedicated machine if you want maximal isolation.
- Use a dedicated Docker context / separate Docker engine if your host must remain “low risk”.

---

## 3) Security and Isolation Model

### Secrets management
- All sensitive values should be stored in `.env`
- Do not commit `.env` (use `.env.example` as template)

### SSH access
- Key-based SSH only (no password auth) into the node containers.
- `authorized_keys` is mounted into each node container.

### Important warning: Docker socket mounts
Some services (Portainer, Woodpecker agent, Promtail) commonly mount `/var/run/docker.sock`. This grants elevated control over the Docker host engine. If you need “no risk to host”, use:
- A VM
- A remote Docker context
- Or remove socket mounts and accept reduced functionality

---

## 4) Initial Bootstrap

### 4.1 Create `.env`
Copy the template:

```bash
cp .env.example .env
# Edit .env and replace all CHANGE_ME entries.
```
## 4.2 Create SSH key for Ansible → nodes
```
mkdir -p ansible/keys
ssh-keygen -t ed25519 -f ansible/keys/id_ed25519 -N ""
cp ansible/keys/id_ed25519.pub ansible/keys/authorized_keys
chmod 600 ansible/keys/id_ed25519 ansible/keys/authorized_keys

```
## 4.3 Generate Harbor core private key 
```
openssl genrsa -out harbor/config/core/private_key.pem 4096
chmod 600 harbor/config/core/private_key.pem

```

## 4.4 Validate Compose model before running
```
docker compose --env-file .env config > /tmp/compose.rendered.yaml
grep -n '\${' /tmp/compose.rendered.yaml || echo "OK: no unresolved variables"

```

## 5) Start / Stop Lifecycle
```
Start
docker compose --env-file .env up -d --build
docker compose ps

Stop (keep volumes/data)
docker compose down

Stop (delete everything including volumes)

WARNING: this destroys Gitea repos, Harbor images, Grafana state, etc.
docker compose down -v

Pull images (diagnose 404s)
docker compose --env-file .env pull --no-parallel

```

## 6) Access URLs (typical)

```
Your ports come from .env. Common defaults:
Gitea: http://localhost:${GITEA_HTTP_PORT}
Woodpecker: http://localhost:${WOODPECKER_HTTP_PORT}
Semaphore: http://localhost:${SEMAPHORE_HTTP_PORT}
Harbor: http://localhost:${HARBOR_HTTP_PORT}
Grafana: http://localhost:${GRAFANA_HTTP_PORT}
Portainer: http://localhost:${PORTAINER_HTTP_PORT}  (or https://${PORTAINER_HTTPS_PORT})
Netdata: http://localhost:${NETDATA_HTTP_PORT}
```
## 7) Ansible Usage
### 7.1 Run Ansible from the ansible-cli container
```
Enter the container:
docker compose exec ansible-cli bash

Verify connectivity:
ansible -i ansible/hosts.ini all -m ping

Run the connectivity playbook:
ansible-playbook -i ansible/hosts.ini ansible/playbooks/00_ping.yml

Run disk check:
ansible-playbook -i ansible/hosts.ini ansible/playbooks/10_check_disk_space.yml

Install nginx on workers:
ansible-playbook -i ansible/hosts.ini ansible/playbooks/20_install_nginx_on_workers.yml

```

## 7.2 Run a role directly (ad-hoc pattern)
```
Create a small one-off playbook if you want role-only execution:
cat > /tmp/run_nginx_role.yml <<'YAML'
- hosts: workers
  roles:
    - nginx
YAML

ansible-playbook -i ansible/hosts.ini /tmp/run_nginx_role.yml

```

## 7.3 Add more worker nodes
```
You have two common patterns:
Pattern A: Clone an existing worker service (explicit worker1/worker2 style)
Copy the worker service stanza in docker-compose.yaml and create lab-worker3.
Add a unique host port mapping for SSH (e.g., 2225:22) and a new docker volume (e.g., worker3_docker_data).
Add it to ansible/hosts.ini:

[workers]
lab-worker1 ansible_user=root ansible_port=22
lab-worker2 ansible_user=root ansible_port=22
lab-worker3 ansible_user=root ansible_port=22

Bring it up:
docker compose --env-file .env up -d --build lab-worker3


Pattern B: Scale a single worker service (recommended for many workers)
If you refactor compose to a single lab-worker service, you can scale:

docker compose --env-file .env up -d --scale lab-worker=5

Your containers will be named like:

<project>-lab-worker-1

<project>-lab-worker-2
...

Then generate inventory dynamically (example):
docker compose ps --format json | jq -r '
  .[] | select(.Service | test("lab-worker")) | .Name
' | awk '
  BEGIN { print "[workers]" }
  { print $1 " ansible_user=root ansible_port=22" }
' > ansible/hosts.workers.generated.ini

```
## 8) Semaphore UI Usage (Ansible from web UI)
### 8.1 Login

Open: http://localhost:${SEMAPHORE_HTTP_PORT}
Use the admin credentials from .env.

## 8.2 Add a Project
Create a project like HomeLab
Add a repository:
Type: “Local” (because the repo is mounted into /work), or “Git” if you use Gitea URL
Path: /work (mounted repo)
Add an inventory:
Inventory file: /work/ansible/hosts.ini
Add a key:
Private key file: /work/ansible/keys/id_ed25519

## 8.3 Create a Task Template
Type: Ansible
Playbook: /work/ansible/playbooks/00_ping.yml
Inventory: the inventory created above
Run it and confirm output.

## 9) Terraform / Terragrunt Usage


```
Enter the tf toolbox container:
docker compose exec tf sh

Run the demo Terragrunt plan/apply:
cd /work/infra/live/dev
terragrunt run-all plan
terragrunt run-all apply
terragrunt run-all destroy



```

## 10) Gitea Usage
```
Open http://localhost:${GITEA_HTTP_PORT} and complete first-run wizard:
Create admin user
Create an organization (optional)
Create a repository (example: demo-app)
Clone from host:

git clone http://localhost:${GITEA_HTTP_PORT}/<user>/demo-app.git

```

## 11) Harbor Usage (Registry + Scanning)
### 11.1 Login and create a project
```
Open http://localhost:${HARBOR_HTTP_PORT}
Login: admin
Password: ${HARBOR_ADMIN_PASSWORD}
Create a project:
Name: devops-lab

```

## 11.2 Create a robot account for CI
```
Harbor → Project → Robot Accounts
Create a robot account and save:

username (robot$...)

token/password
```


## 11.3 Test push/pull from inside the lab network (recommended)
```
From the master node container:
docker exec -it lab-master bash
docker login harbor-nginx:8080
# user: robot$... or a Harbor user
# pass: token/password

docker pull alpine:3.20
docker tag alpine:3.20 harbor-nginx:8080/devops-lab/alpine:3.20
docker push harbor-nginx:8080/devops-lab/alpine:3.20


```

## 11.4 Register Trivy scanner adapter

```
Harbor UI:
Administration → Interrogation Services / Scanners
Add scanner:
Name: trivy
Endpoint: http://harbor-trivy:8080
Auth: none
Set it as default scanner for projects (optional).
Then trigger a scan on an image in a project.

```

## 12) Woodpecker CI/CD (Gitea → Build → Push to Harbor)
### 12.1 Configure OAuth in Gitea
```
In Gitea:
Settings → Applications → OAuth2 Applications → New
Callback URL must match:
http://localhost:${WOODPECKER_HTTP_PORT}/authorize
Put the Client ID/Secret into .env:
WOODPECKER_GITEA_CLIENT=...
WOODPECKER_GITEA_SECRET=...
Restart:

docker compose restart woodpecker-server woodpecker-agent


```
### 12.2 Enable repo in Woodpecker
```
Open: http://localhost:${WOODPECKER_HTTP_PORT}
Login via Gitea
Enable your repository
```


### 12.3 Add Harbor credentials as Woodpecker secrets
```
In Woodpecker repo → Secrets:
harbor_username = robot/user
harbor_password = robot token/password
```


### 12.4 Example pipeline: build/push to Harbor
```
Add .woodpecker.yml in your repo. Example:

variables:
  HARBOR_REGISTRY: &harbor_registry "harbor-nginx:8080"
  HARBOR_PROJECT:  &harbor_project  "devops-lab"

steps:
  - name: build-and-push-to-harbor
    image: woodpeckerci/plugin-docker-buildx:2
    privileged: true
    settings:
      repo: *harbor_registry/*harbor_project/${CI_REPO_NAME}
      registry: *harbor_registry
      insecure: true
      context: .
      dockerfile: Dockerfile
      auto_tag: true
      default_tag: latest
      tags:
        - ${CI_COMMIT_SHA}
      username:
        from_secret: harbor_username
      password:
        from_secret: harbor_password

    when:
      event:
        - push
        - tag

```
### 12.5 Optional: “Deploy” stage using Ansible

```
You can add another step to run Ansible after pushing (lab use case: deploy a container to workers or install packages).
Example:
Run ansible-cli style execution inside pipeline (install ansible, use mounted keys as pipeline secrets)
For best security, store the SSH private key as a CI secret and write it to a temp file in the pipeline step.

```



## 13) Observability (Grafana + Loki + Tempo)
### 13.1 Logs in Loki
```
Promtail discovers Docker containers (via Docker socket) and pushes logs to Loki.
In Grafana (Explore):
Select Loki datasource
Query:

{container=~".+"} (all containers)
{container="gitea"} (specific)
```


## 13.2 Traces in Tempo
```
Tempo accepts OTLP:
gRPC: tempo:4317
HTTP: tempo:4318

Example: Send a synthetic trace (recommended way)

Run a small test emitter container on the same network.
(If you already have an app, simply configure OTEL exporter to tempo:4317.)
Once traces exist:
Grafana → Explore → Tempo datasource
Search for traces by service name or attributes
```

## 13.3 Dashboard provisioning
```
If you provision dashboards from disk:
Place dashboards under observability/grafana/dashboards/
Provision provider under observability/grafana/provisioning/dashboards/
Restart Grafana:
docker compose restart grafana

```

## 14) Troubleshooting
```
Validate the resolved compose
docker compose --env-file .env config
docker compose --env-file .env pull --no-parallel
docker compose logs -n 200 <service>

```

### Common: Harbor takes time to initialize
``` 
Harbor has multiple dependencies and may take several minutes on first boot.
Check Harbor-related logs and ensure DB/redis are up.

Reset everything
docker compose down -v
docker volume ls | grep homelab


```

# Operational Best Practices

Keep .env out of Git.
Prefer robot accounts for registry + CI.
Use a VM if you want isolation from your workstation.
Monitor resource usage: Harbor + Grafana stack is RAM-heavy.




# Additional practical examples you can add immediately

## A) Add a “CI deploy to workers” use case (end-to-end)
A typical homelab CI/CD story that’s realistic:
1) Developer pushes to Gitea
2) Woodpecker builds image
3) Woodpecker pushes to Harbor
4) Woodpecker runs Ansible to deploy that image onto worker nodes

To do this cleanly:
- Store `SSH_PRIVATE_KEY` as a Woodpecker secret
- In the pipeline, write it to `/tmp/id_ed25519`, `chmod 600`, then run `ansible-playbook` targeting workers and running `docker run` on them (since workers have Docker daemon in-container)

## B) Add a “GitOps-lite” use case
- Store Ansible playbooks + Terragrunt config in Gitea
- Semaphore watches the repo (or you manually pull) and you execute:
  - `terragrunt plan/apply` from Semaphore
  - then `ansible-playbook` from Semaphore
This simulates “pipeline-less” orchestration through a controlled UI.

## C) Add an Observability “smoke test”
- Query Loki for `container="woodpecker-server"` logs
- Push a synthetic trace to Tempo (once you have an emitter) and verify it appears in Grafana Tempo Explore.

