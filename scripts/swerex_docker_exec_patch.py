"""Patch swerex DockerDeployment to use docker exec instead of swerex HTTP server.

This avoids the need to install swerex/Python inside SWE-bench Pro containers.
The container runs with a sleep entrypoint, and all commands go through docker exec.

Usage:
    python exp1/swerex_docker_exec_patch.py          # Apply patch
    python exp1/swerex_docker_exec_patch.py --revert  # Revert to original
"""

import asyncio
import base64
import logging
import os
import shlex
import subprocess
import tempfile
import time
import uuid
from pathlib import Path
from typing import Any

from typing_extensions import Self

from swerex.deployment.abstract import AbstractDeployment
from swerex.deployment.config import DockerDeploymentConfig
from swerex.deployment.hooks.abstract import CombinedDeploymentHook, DeploymentHook
from swerex.exceptions import DeploymentNotStartedError, DockerPullError
from swerex.runtime.abstract import AbstractRuntime, IsAliveResponse

# Import with fallbacks for different swe-rex versions
try:
    from swerex.runtime.abstract import (
        Action, BashAction, BashInterruptAction, BashObservation,
        CloseResponse, Command, CommandResponse,
        Observation, ReadFileRequest, ReadFileResponse,
        UploadRequest, UploadResponse, WriteFileRequest, WriteFileResponse,
    )
except ImportError:
    pass

# Session types differ between versions
try:
    from swerex.runtime.abstract import CreateSessionRequest, CreateSessionResponse, CloseSessionRequest, CloseSessionResponse
except ImportError:
    CreateSessionRequest = None
    CreateSessionResponse = None
    CloseSessionRequest = None
    CloseSessionResponse = None

try:
    from swerex.runtime.abstract import CreateBashSessionRequest, CreateBashSessionResponse, CloseBashSessionRequest, CloseBashSessionResponse
except ImportError:
    CreateBashSessionRequest = None
    CreateBashSessionResponse = None
    CloseBashSessionRequest = None
    CloseBashSessionResponse = None
from swerex.utils.log import get_logger


class DockerExecRuntime(AbstractRuntime):
    """Runtime that uses docker exec instead of swerex HTTP server."""

    def __init__(self, container_name: str, logger: logging.Logger | None = None):
        self._container_name = container_name
        self.logger = logger or get_logger("rex-docker-exec")
        self._sessions: dict[str, bool] = {}

    def _docker_exec(self, cmd: str, timeout: float = 30) -> tuple[str, str, int]:
        """Run a command inside the container via docker exec."""
        # Prepend PATH and PYTHONPATH setup for swe-agent tools
        setup = (
            'export PATH="/root/tools/registry/bin:/root/tools/edit_anthropic/bin:'
            '/root/tools/review_on_submit_m/bin:/root/tools/forfeit/bin:$PATH"; '
            'export PYTHONPATH="/root/registry_shim:/root/tools/registry/lib:$PYTHONPATH"; '
            'export ROOT=/app; '
        )
        full_cmd = setup + cmd
        try:
            result = subprocess.run(
                ["docker", "exec", self._container_name, "/bin/bash", "-c", full_cmd],
                capture_output=True,
                timeout=timeout,
            )
            stdout = result.stdout.decode("utf-8", errors="replace")
            stderr = result.stderr.decode("utf-8", errors="replace")
            return stdout, stderr, result.returncode
        except subprocess.TimeoutExpired:
            return "", f"Command timed out after {timeout}s", 1

    async def is_alive(self, *, timeout: float | None = None) -> IsAliveResponse:
        try:
            result = subprocess.run(
                ["docker", "inspect", "-f", "{{.State.Running}}", self._container_name],
                capture_output=True, text=True, timeout=5,
            )
            alive = "true" in result.stdout.lower()
            return IsAliveResponse(is_alive=alive)
        except Exception:
            return IsAliveResponse(is_alive=False)

    async def create_session(self, request) -> Any:
        name = getattr(request, 'name', 'default')
        self._sessions[name] = True
        # Return appropriate response type
        if CreateBashSessionResponse is not None:
            return CreateBashSessionResponse()
        if CreateSessionResponse is not None:
            return CreateSessionResponse()
        from pydantic import BaseModel
        class GenericResponse(BaseModel):
            pass
        return GenericResponse()

    async def run_in_session(self, action) -> Any:
        if hasattr(action, '__class__') and 'Interrupt' in action.__class__.__name__:
            return BashObservation(output="", exit_code=0)
        if hasattr(action, 'command'):
            timeout = getattr(action, 'timeout', 30) or 30
            stdout, stderr, rc = self._docker_exec(action.command, timeout=timeout)
            output = stdout
            if stderr:
                output += stderr
            return BashObservation(output=output, exit_code=rc)
        return BashObservation(output="Unknown action type", exit_code=1)

    async def execute(self, command: Command) -> CommandResponse:
        timeout = command.timeout if hasattr(command, 'timeout') and command.timeout else 30
        cmd_str = command.command
        stdout, stderr, rc = self._docker_exec(cmd_str, timeout=timeout)
        return CommandResponse(stdout=stdout, stderr=stderr, returncode=rc)

    async def read_file(self, request: ReadFileRequest) -> ReadFileResponse:
        stdout, stderr, rc = self._docker_exec(f"cat {shlex.quote(request.path)}")
        if rc != 0:
            raise FileNotFoundError(f"File not found: {request.path}: {stderr}")
        return ReadFileResponse(content=stdout)

    async def write_file(self, request: WriteFileRequest) -> WriteFileResponse:
        # Use base64 to safely transfer content with special chars
        b64 = base64.b64encode(request.content.encode()).decode()
        self._docker_exec(f"echo {shlex.quote(b64)} | base64 -d > {shlex.quote(request.path)}")
        return WriteFileResponse()

    async def upload(self, request: UploadRequest) -> UploadResponse:
        """Upload a file/directory from host to container using docker cp."""
        src = request.source_path
        target = request.target_path
        # Ensure parent directory exists
        parent = os.path.dirname(target)
        if parent:
            self._docker_exec(f"mkdir -p {shlex.quote(parent)}")
        dst = f"{self._container_name}:{target}"
        result = subprocess.run(
            ["docker", "cp", src, dst],
            capture_output=True, text=True, timeout=120,
        )
        if result.returncode != 0:
            self.logger.error(f"docker cp failed: {result.stderr}")
            # Fallback: tar + docker exec for directories
            if os.path.isdir(src):
                import tarfile, io
                tar_buf = io.BytesIO()
                with tarfile.open(fileobj=tar_buf, mode='w:gz') as tar:
                    tar.add(src, arcname=os.path.basename(src))
                tar_bytes = tar_buf.getvalue()
                b64 = base64.b64encode(tar_bytes).decode()
                # Split into chunks to avoid arg length limits
                chunk_size = 50000
                self._docker_exec(f"mkdir -p {shlex.quote(target)}")
                self._docker_exec(f"rm -f /tmp/_upload.tar.gz")
                for i in range(0, len(b64), chunk_size):
                    chunk = b64[i:i+chunk_size]
                    self._docker_exec(f"echo -n {shlex.quote(chunk)} >> /tmp/_upload.b64")
                self._docker_exec(f"base64 -d /tmp/_upload.b64 > /tmp/_upload.tar.gz")
                self._docker_exec(f"tar xzf /tmp/_upload.tar.gz -C {shlex.quote(parent)}")
                self._docker_exec(f"rm -f /tmp/_upload.tar.gz /tmp/_upload.b64")
            else:
                raise RuntimeError(f"docker cp failed: {result.stderr}")
        return UploadResponse()

    async def close_session(self, request) -> Any:
        name = getattr(request, 'name', 'default')
        self._sessions.pop(name, None)
        if CloseBashSessionResponse is not None:
            return CloseBashSessionResponse()
        if CloseSessionResponse is not None:
            return CloseSessionResponse()
        from pydantic import BaseModel
        class GenericResponse(BaseModel):
            pass
        return GenericResponse()

    async def close(self) -> CloseResponse:
        return CloseResponse()


def _is_image_available(image: str) -> bool:
    try:
        subprocess.check_call(["docker", "inspect", image], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return True
    except subprocess.CalledProcessError:
        return False


def _pull_image(image: str) -> bytes:
    try:
        return subprocess.check_output(["docker", "pull", image], stderr=subprocess.PIPE)
    except subprocess.CalledProcessError as e:
        raise subprocess.CalledProcessError(e.returncode, e.cmd, e.output, e.stderr) from None


def _remove_image(image: str) -> bytes:
    return subprocess.check_output(["docker", "rmi", image], timeout=30)


class DockerExecDeployment(AbstractDeployment):
    """Docker deployment using docker exec instead of swerex HTTP server.

    Drop-in replacement for DockerDeployment that works with any container
    (no need to install swerex inside).
    """

    def __init__(self, *, logger: logging.Logger | None = None, **kwargs: Any):
        self._config = DockerDeploymentConfig(**kwargs)
        self._runtime: DockerExecRuntime | None = None
        self._container_process = None
        self._container_name = None
        self.logger = logger or get_logger("rex-deploy")
        self._hooks = CombinedDeploymentHook()

    def add_hook(self, hook: DeploymentHook):
        self._hooks.add_hook(hook)

    @classmethod
    def from_config(cls, config: DockerDeploymentConfig) -> Self:
        return cls(**config.model_dump())

    def _get_container_name(self) -> str:
        image_name_sanitized = "".join(c for c in self._config.image if c.isalnum() or c in "-_.")
        return f"{image_name_sanitized}-{uuid.uuid4()}"

    @property
    def container_name(self) -> str | None:
        return self._container_name

    async def is_alive(self, *, timeout: float | None = None) -> IsAliveResponse:
        if self._runtime is None:
            raise RuntimeError("Runtime not started")
        return await self._runtime.is_alive(timeout=timeout)

    def _pull_image(self) -> None:
        if self._config.pull == "never":
            return
        if self._config.pull == "missing" and _is_image_available(self._config.image):
            return
        self.logger.info(f"Pulling image {self._config.image!r}")
        self._hooks.on_custom_step("Pulling docker image")
        try:
            _pull_image(self._config.image)
        except subprocess.CalledProcessError as e:
            msg = f"Failed to pull image {self._config.image}. "
            msg += f"Error: {e.stderr.decode()}"
            raise DockerPullError(msg) from e

    async def start(self):
        """Start container with sleep entrypoint, use docker exec for commands."""
        self._pull_image()
        # No image building needed - use the image as-is
        image_id = self._config.image
        self._container_name = self._get_container_name()

        platform_arg = []
        if self._config.platform is not None:
            platform_arg = ["--platform", self._config.platform]

        # Start container with sleep entrypoint (keeps it running)
        cmds = [
            "docker", "run", "--rm", "-d",
            *platform_arg,
            "--cpus=4",
            "--memory=4g",
            "--entrypoint", "/bin/bash",
            *self._config.docker_args,
            "--name", self._container_name,
            image_id,
            "-c", "sleep 99999",
        ]
        self.logger.info(f"Starting container {self._container_name} with image {self._config.image}")
        self.logger.debug(f"Command: {shlex.join(cmds)!r}")

        result = subprocess.run(cmds, capture_output=True, text=True)
        if result.returncode != 0:
            raise RuntimeError(f"Failed to start container: {result.stderr}")

        self._runtime = DockerExecRuntime(self._container_name, logger=self.logger)

        # Upload registry shim so swe-agent tools can use it
        registry_shim_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "registry_shim")
        if os.path.exists(registry_shim_dir):
            subprocess.run(
                ["docker", "cp", registry_shim_dir, f"{self._container_name}:/root/registry_shim"],
                capture_output=True, timeout=30,
            )
            self.logger.info("Uploaded registry shim to container")

        # Wait for container to be ready
        for i in range(10):
            alive = await self._runtime.is_alive()
            if alive.is_alive:
                self.logger.info("Container started successfully")
                return
            time.sleep(1)
        raise RuntimeError("Container did not start in time")

    async def stop(self):
        if self._runtime is not None:
            await self._runtime.close()
            self._runtime = None
        if self._container_name is not None:
            try:
                subprocess.check_call(
                    ["docker", "kill", self._container_name],
                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=10,
                )
            except (subprocess.CalledProcessError, subprocess.TimeoutExpired):
                pass
            self._container_name = None

        if self._config.remove_images and _is_image_available(self._config.image):
            try:
                _remove_image(self._config.image)
            except subprocess.CalledProcessError:
                pass

    @property
    def runtime(self) -> DockerExecRuntime:
        if self._runtime is None:
            raise DeploymentNotStartedError()
        return self._runtime


def apply_patch():
    """Replace DockerDeployment with DockerExecDeployment in swerex."""
    import swerex.deployment.docker as docker_module

    # Save originals
    docker_module._OriginalDockerDeployment = docker_module.DockerDeployment

    # Replace
    docker_module.DockerDeployment = DockerExecDeployment

    # Also patch the import in swerex.deployment
    import swerex.deployment as deployment_module
    if hasattr(deployment_module, 'DockerDeployment'):
        deployment_module.DockerDeployment = DockerExecDeployment

    print("Patched DockerDeployment -> DockerExecDeployment (using docker exec)")


def apply_patch_to_file():
    """Write the patched docker.py to swerex installation."""
    import swerex
    swerex_dir = os.path.dirname(swerex.__file__)
    target = os.path.join(swerex_dir, "deployment", "docker.py")

    # Read this file
    source = os.path.abspath(__file__)

    # Generate the patched docker.py
    patched = f'''"""Patched docker.py - uses docker exec instead of swerex HTTP server.
Original backed up as docker.py.original
"""
import sys
sys.path.insert(0, "{os.path.dirname(source)}")
from swerex_docker_exec_patch import DockerExecDeployment as DockerDeployment, DockerExecRuntime
from swerex.deployment.config import DockerDeploymentConfig

__all__ = ["DockerDeployment", "DockerDeploymentConfig"]
'''

    # Backup original
    backup = target + ".original"
    if not os.path.exists(backup):
        import shutil
        shutil.copy2(target, backup)
        print(f"Backed up original to {backup}")

    with open(target, "w") as f:
        f.write(patched)
    print(f"Patched {target}")


def revert_patch():
    """Revert to original docker.py."""
    import swerex
    swerex_dir = os.path.dirname(swerex.__file__)
    target = os.path.join(swerex_dir, "deployment", "docker.py")
    backup = target + ".original"

    if os.path.exists(backup):
        import shutil
        shutil.copy2(backup, target)
        print(f"Reverted {target}")
    else:
        print("No backup found")


if __name__ == "__main__":
    import sys
    if "--revert" in sys.argv:
        revert_patch()
    else:
        apply_patch_to_file()
