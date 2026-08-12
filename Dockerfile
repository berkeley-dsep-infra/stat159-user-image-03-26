FROM us-central1-docker.pkg.dev/ucb-datahub-2018/base-images-repo/base-r-pixi-image:3f3378e AS solver

# ------------------------------------------------------------
# Solve this image's additional packages with pixi, against a fixed pin
# for every package already installed in the base image (extracted from
# this same image, live) -- so pixi can never silently substitute something
# already there, it either respects it or the solve fails loudly. See
# pixi.toml/scripts/ comments and dedupe-explicit-spec.py for the two real
# issues this caught: a jupyter-ai/pyjwt conflict, and a conda-forge package
# (localtileserver) that lists both the old and new name of a renamed
# dependency, which would otherwise silently corrupt one of them.
# pixi never touches /srv/conda and is not present in the final image;
# mamba (already present, inherited from the base) does the real,
# no-solve install of pixi's already-resolved package list below.
# ------------------------------------------------------------
USER root
RUN curl -fsSL https://pixi.sh/install.sh | PIXI_HOME=/opt/pixi sh
ENV PATH=/opt/pixi/bin:$PATH

USER ${NB_USER}
WORKDIR /tmp/solve
COPY --chown=${NB_USER}:${NB_USER} pixi.toml scripts/merge-base-manifest.py scripts/pixi-pypi-requirements.py scripts/dedupe-explicit-spec.py ./

RUN mamba list -n notebook --export | tail -n +3 > /tmp/base-manifest.txt && \
    python3 merge-base-manifest.py /tmp/base-manifest.txt pixi.toml /tmp/merged-pixi.toml && \
    mkdir merged && cp /tmp/merged-pixi.toml merged/pixi.toml && \
    (cd merged && pixi install) && \
    (cd merged && pixi workspace export conda-explicit-spec --platform linux-64 --ignore-pypi-errors /tmp/spec-out) && \
    python3 dedupe-explicit-spec.py /tmp/spec-out/*_conda_spec.txt /tmp/explicit.txt && \
    (cd merged && pixi list --json) | python3 pixi-pypi-requirements.py > /tmp/pip-requirements.txt

# ===================================================================
# Final image
# ===================================================================
FROM us-central1-docker.pkg.dev/ucb-datahub-2018/base-images-repo/base-r-pixi-image:3f3378e

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
