FROM quay.io/jupyter/pytorch-notebook:cuda12-python-3.11.8

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

USER root

# Install Git, GitHub CLI, and SSH tooling.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        git \
        gpg \
        openssh-client \
        wget \
	gh \
    && rm -rf /var/lib/apt/lists/*

USER ${NB_UID}

ENV PATH="/home/jovyan/.opencode/bin:${PATH}"
ENV OPENCODE_PORT="4096"

RUN curl -fsSL https://opencode.ai/install | bash

RUN mkdir -p \
        /home/jovyan/work \
        /home/jovyan/.config/opencode \
        /home/jovyan/.cache/opencode \
        /home/jovyan/.config/gh

RUN python -m pip install --no-cache-dir \
        aiobotocore==2.12.3 \
        boto3==1.34.69 \
        fsspec==2024.3.1 \
        python-dotenv==1.2.2 \
        s3fs==2024.3.1

USER root

COPY start-services.sh /usr/local/bin/start-services.sh

RUN chmod 0755 /usr/local/bin/start-services.sh \
    && chown ${NB_UID}:${NB_GID} /usr/local/bin/start-services.sh \
    && fix-permissions /home/jovyan

USER ${NB_UID}

WORKDIR /home/jovyan/work

EXPOSE 8888 4096

CMD ["/usr/local/bin/start-services.sh"]
