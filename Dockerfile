FROM nousresearch/hermes-agent:latest

LABEL org.opencontainers.image.source="https://github.com/apple050620312/HermesPterodactyl"
LABEL org.opencontainers.image.description="Hermes Agent runtime adapted for Pterodactyl Wings"
LABEL org.opencontainers.image.licenses="MIT"

USER root

# Pterodactyl expects this account and home directory to exist. Wings replaces
# the image user with its own numeric UID/GID at runtime, while mounting the
# server volume at /home/container.
RUN useradd --create-home --home-dir /home/container --shell /bin/bash container

COPY --chmod=0755 docker/entrypoint.sh /entrypoint.sh

ENV USER=container \
    HOME=/home/container \
    HERMES_HOME=/home/container \
    HERMES_WRITE_SAFE_ROOT=/home/container \
    HERMES_LAZY_INSTALL_TARGET=/home/container/lazy-packages \
    HERMES_GATEWAY_NO_SUPERVISE=1 \
    PATH=/opt/hermes/bin:/opt/hermes/.venv/bin:/home/container/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

WORKDIR /home/container
USER container

# Wings supplies STARTUP as an environment variable. This wrapper bootstraps
# the persistent config, optionally starts the dashboard, and then runs STARTUP.
ENTRYPOINT []
CMD ["/bin/bash", "/entrypoint.sh"]
