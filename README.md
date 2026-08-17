# Remote Jupyter and OpenCode

This container runs JupyterLab, VS Code, and OpenCode Web against the same workspace. Docker publishes the authenticated services on the VM's network interfaces by default.

## Launch on Chameleon

Run one of these notebooks in the Chameleon Jupyter environment:

- `launch-cpu.ipynb` reserves an `m1.large` VM with an optional disposable boot volume.
- `launch-gpu.ipynb` reserves a `g1.h100.pci.1` VM with a CUDA image and a 100 GiB disposable boot volume by default.
- `cleanup.ipynb` deletes the selected VM, floating IP, disposable volume, and lease.

The launch notebooks expose `LEASE_DAYS`, `VOLUME_SIZE_GB`, and `PUBLIC_GIT_REPOSITORY_URL`. Leave the repository URL blank to create an empty Git repository, or supply a public HTTPS URL to clone it. The notebooks create inbound security-group rules for SSH, Jupyter, and OpenCode; assign a floating IP; generate reusable CHI@TACC S3 credentials; and start the container. The S3 credentials are written to `project/.env`, loaded into Jupyter and OpenCode, and excluded from Git by `project/.gitignore`.

OpenCode uses the bundled Kilo anonymous provider by default. Its configuration disables the `amazon-bedrock` provider so OpenCode does not interpret Chameleon's AWS-compatible S3 credentials as LLM credentials.

Run each notebook from the directory containing the Docker and Compose files in this package.

## Start the services

Create `.env` from `.env.example`, then replace both token placeholders. You can generate each token with `openssl rand -hex 24`.

```bash
docker compose up --build -d
docker compose ps
```

To enable OpenCode host access in a manual deployment, set `HOST_SSH_ENABLED=1` and run:

```bash
sudo ./setup-host-access.sh "$PWD/host-ssh"
docker compose -f compose.yaml -f compose.host.yaml up --build -d
```

Add `-f compose.host.yaml` to later Compose commands. The launch notebooks configure host access automatically.

On a VM with an NVIDIA GPU, NVIDIA Container Toolkit, and a working `nvidia-smi`, add the GPU overlay:

```bash
docker compose -f compose.yaml -f compose.gpu.yaml up --build -d
```

If host access is enabled, include both overlays:

```bash
docker compose -f compose.yaml -f compose.gpu.yaml -f compose.host.yaml up --build -d
```

Follow startup logs with:

```bash
docker compose logs -f jupyter
```

On first startup, the container creates or clones `/home/jovyan/work/<OPENCODE_PROJECT_DIR>` and opens it as OpenCode's default project. The default directory is `/home/jovyan/work/project`. JupyterLab keeps `/home/jovyan/work` as its root so it can access every project in the workspace.

## Open the browser interfaces

Open JupyterLab at `http://<FLOATING_IP>:8888/lab?token=<JUPYTER_TOKEN>`.

Open VS Code at `http://<FLOATING_IP>:8888/vscode/?token=<JUPYTER_TOKEN>&folder=/home/jovyan/work/project`.

Open the project in OpenCode at `http://<FLOATING_IP>:4096/L2hvbWUvam92eWFuL3dvcmsvcHJvamVjdA==/session`. Sign in with the `OPENCODE_SERVER_USERNAME` and `OPENCODE_SERVER_PASSWORD` values from `.env`.

The cloud security group must allow inbound TCP ports 8888 and 4096. Direct HTTP access does not encrypt credentials or session traffic. Set `BIND_ADDRESS=127.0.0.1` and use SSH forwarding when you need encrypted transport.

## Host access from OpenCode

Each launch notebook creates an `opencode` user on the VM host and grants it passwordless sudo access. The notebook generates a dedicated SSH key, mounts the private key read-only in the container, and pins the host's SSH keys. The container remains unprivileged.

The startup script creates `HOST.md`, unless the repository already contains that file, with the command OpenCode can use to run host commands:

```bash
ssh -i /home/jovyan/.ssh/id_ed25519 -o BatchMode=yes -o IdentitiesOnly=yes -o UpdateHostKeys=no opencode@host.docker.internal '<command>'
```

Prefix the remote command with `sudo` when it requires root access. Anyone who can execute commands in the container can use this key for root-equivalent access to the VM.

## Check GPU access

Run these checks only when you started the service with `compose.gpu.yaml`.

```bash
docker compose exec jupyter nvidia-smi
docker compose exec jupyter python -c 'import torch; print(torch.cuda.is_available()); print(torch.cuda.get_device_name(0))'
```

Your notebooks and repositories persist under `JUPYTER_DATA_DIR`. OpenCode and GitHub CLI settings persist in named Docker volumes.
