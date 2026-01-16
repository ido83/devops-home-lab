FROM ubuntu:22.04

ARG DEBIAN_FRONTEND=noninteractive

# ------------------------------------------------------------------------------
# Ubuntu-based "server node" with:
# - OpenSSH server for Ansible connectivity
# - Docker Engine (dockerd) to simulate DinD
# - Python for Ansible modules
# - Supervisor to run multiple daemons in one container
# ------------------------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl \
      openssh-server openssh-client \
      python3 python3-apt \
      iproute2 iputils-ping \
      supervisor \
      docker.io containerd \
      iptables \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /var/run/sshd /root/.ssh && chmod 700 /root/.ssh

COPY sshd_config /etc/ssh/sshd_config
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 22 2375
ENTRYPOINT ["/entrypoint.sh"]

