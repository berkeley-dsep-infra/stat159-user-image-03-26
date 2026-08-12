FROM us-central1-docker.pkg.dev/ucb-datahub-2018/base-images-repo/base-r-pixi-image:dac24b5 AS solver

# ------------------------------------------------------------
# Solve this image's additional packages with pixi, against a fixed pin
# for every package already installed in the base image (extracted from
# this same image, live) -- so pixi can never silently substitute something
# already there, it either respects it or the solve fails loudly.
# pixi never touches /srv/conda and is not present in the final image;
# mamba (already present, inherited from the base) does the real,
# no-solve install of pixi's already-resolved package list below.
# ------------------------------------------------------------
USER root
RUN curl -fsSL https://pixi.sh/install.sh | PIXI_HOME=/opt/pixi sh
ENV PATH=/opt/pixi/bin:$PATH
RUN install -d -o ${NB_USER} -g ${NB_USER} /tmp/solve

USER ${NB_USER}
WORKDIR /tmp/solve
COPY --chown=${NB_USER}:${NB_USER} pixi.toml ./

RUN /opt/pixi-solve/solve.sh

# ===================================================================
# Final image
# ===================================================================
FROM us-central1-docker.pkg.dev/ucb-datahub-2018/base-images-repo/base-r-pixi-image:dac24b5

# ------------------------------------------------------------
# System packages
# ------------------------------------------------------------
USER root
COPY apt.txt /tmp/apt.txt
RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends $(grep -v '^#' /tmp/apt.txt) && \
    apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/apt.txt

# ------------------------------------------------------------
# Conda / Python packages
# ------------------------------------------------------------
USER ${NB_USER}
COPY --from=solver --chown=${NB_USER}:${NB_USER} /tmp/explicit.txt /tmp/pip-requirements.txt /tmp/
RUN mamba install -n notebook --file /tmp/explicit.txt -y && \
    pip install --no-cache-dir -r /tmp/pip-requirements.txt && \
    mamba clean -afy && rm -f /tmp/explicit.txt /tmp/pip-requirements.txt

# ------------------------------------------------------------
# VS Code extensions
# ------------------------------------------------------------
USER root
ENV VSCODE_EXTENSIONS=${CONDA_DIR}/envs/notebook/share/code-server/extensions
RUN install -d -o ${NB_USER} -g ${NB_USER} ${VSCODE_EXTENSIONS}

USER ${NB_USER}
RUN code-server --extensions-dir ${VSCODE_EXTENSIONS} --install-extension ms-toolsai.jupyter && \
    code-server --extensions-dir ${VSCODE_EXTENSIONS} --install-extension ms-python.python && \
    code-server --extensions-dir ${VSCODE_EXTENSIONS} --install-extension quarto.quarto

# ------------------------------------------------------------
# R packages
# ------------------------------------------------------------
WORKDIR /home/${NB_USER}
COPY --chown=${NB_USER}:${NB_USER} install.r /tmp/install.r
RUN Rscript /tmp/install.r && rm -rf /tmp/install.r /tmp/downloaded_packages/ /tmp/*.rds

USER ${NB_USER}

EXPOSE 8888
ENTRYPOINT ["tini", "--"]
