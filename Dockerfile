FROM us-central1-docker.pkg.dev/ucb-datahub-2018/base-images-repo/base-python-image:bbe5fda

USER root

RUN apt-get update && apt-get install -y tini && rm -rf /var/lib/apt/lists/*

# ------------------------------------------------------------
# System packages
# ------------------------------------------------------------
# Copy your new apt.txt
COPY apt.txt /tmp/apt.txt

RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends $(grep -v '^#' /tmp/apt.txt) && \
    apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/apt.txt

# ------------------------------------------------------------
# Conda / Python packages
# ------------------------------------------------------------
# Copy environment.yml for additional packages
USER ${NB_USER}
COPY --chown=${NB_USER}:${NB_USER} environment.yml /tmp/environment.yml


# Update existing /srv/conda/notebook environment with new packages
RUN mamba env update -n notebook -f /tmp/environment.yml && \
    mamba clean -afy && rm -rf /tmp/environment.yml



# ------------------------------------------------------------
# Cleanup
# ------------------------------------------------------------
USER root
RUN rm -rf /tmp/*

USER ${NB_USER}
WORKDIR /home/${NB_USER}


EXPOSE 8888

ENTRYPOINT ["tini", "--"]
