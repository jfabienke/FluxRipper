#!/usr/bin/env python3
"""
FluxRipper Remote Build System

Enables FPGA builds on remote Linux server while developing on Mac.
Optimized for Apple Silicon Macs that can't run Vivado natively.

Created: 2025-12-07 17:10
License: BSD-3-Clause
"""

import subprocess
import os
import sys
import time
import argparse
import json
from pathlib import Path
from dataclasses import dataclass
from typing import Optional
import threading

#==============================================================================
# Configuration
#==============================================================================

@dataclass
class RemoteConfig:
    """Remote build server configuration."""
    # Remote server
    host: str = "build-server"  # SSH host (from ~/.ssh/config)
    user: str = ""  # If not in ssh config
    port: int = 22

    # Paths
    local_project: Path = Path(__file__).parent.parent.parent
    remote_project: str = "~/FluxRipper"

    # Vivado
    vivado_path: str = "/opt/Xilinx/Vivado/2024.1/bin/vivado"

    # Sync
    exclude_patterns: list = None

    def __post_init__(self):
        if self.exclude_patterns is None:
            self.exclude_patterns = [
                ".git",
                "*.bit",
                "*.bin",
                "*.o",
                "*.vvp",
                ".Xil",
                "*.jou",
                "*.log",
                "__pycache__",
                ".DS_Store",
                "build/.cache",
            ]

    @property
    def ssh_target(self) -> str:
        if self.user:
            return f"{self.user}@{self.host}"
        return self.host

    def load_from_file(self, path: Path):
        """Load config from JSON file."""
        if path.exists():
            data = json.loads(path.read_text())
            for key, value in data.items():
                if hasattr(self, key):
                    setattr(self, key, value)

    def save_to_file(self, path: Path):
        """Save config to JSON file."""
        data = {
            "host": self.host,
            "user": self.user,
            "port": self.port,
            "remote_project": self.remote_project,
            "vivado_path": self.vivado_path,
        }
        path.write_text(json.dumps(data, indent=2))


#==============================================================================
# Remote Operations
#==============================================================================

class RemoteBuilder:
    """Handles remote build operations."""

    def __init__(self, config: RemoteConfig):
        self.config = config
        self.build_thread: Optional[threading.Thread] = None
        self.build_status = "idle"
        self.build_log: list = []

    def ssh_cmd(self, command: str, capture: bool = True) -> subprocess.CompletedProcess:
        """Execute command on remote server."""
        ssh_args = [
            "ssh",
            "-p", str(self.config.port),
            self.config.ssh_target,
            command
        ]

        if capture:
            return subprocess.run(ssh_args, capture_output=True, text=True)
        else:
            return subprocess.run(ssh_args)

    def check_connection(self) -> bool:
        """Verify SSH connection works."""
        print(f"Checking connection to {self.config.ssh_target}...")
        result = self.ssh_cmd("echo 'connected'")
        if result.returncode == 0 and "connected" in result.stdout:
            print("  Connection OK")
            return True
        print(f"  Connection failed: {result.stderr}")
        return False

    def check_vivado(self) -> bool:
        """Verify Vivado is available on remote."""
        print("Checking Vivado installation...")
        result = self.ssh_cmd(f"{self.config.vivado_path} -version")
        if result.returncode == 0:
            version = result.stdout.strip().split('\n')[0]
            print(f"  {version}")
            return True
        print(f"  Vivado not found at {self.config.vivado_path}")
        return False

    def sync_to_remote(self) -> bool:
        """Sync local project to remote server."""
        print("Syncing project to remote...")

        exclude_args = []
        for pattern in self.config.exclude_patterns:
            exclude_args.extend(["--exclude", pattern])

        rsync_args = [
            "rsync",
            "-avz",
            "--delete",
            "-e", f"ssh -p {self.config.port}",
        ] + exclude_args + [
            f"{self.config.local_project}/",
            f"{self.config.ssh_target}:{self.config.remote_project}/"
        ]

        start = time.time()
        result = subprocess.run(rsync_args, capture_output=True, text=True)
        elapsed = time.time() - start

        if result.returncode == 0:
            print(f"  Synced in {elapsed:.1f}s")
            return True
        print(f"  Sync failed: {result.stderr}")
        return False

    def sync_from_remote(self, pattern: str = "*.bit") -> bool:
        """Sync build artifacts from remote."""
        print(f"Fetching {pattern} from remote...")

        rsync_args = [
            "rsync",
            "-avz",
            "-e", f"ssh -p {self.config.port}",
            "--include", pattern,
            "--include", "*/",
            "--exclude", "*",
            f"{self.config.ssh_target}:{self.config.remote_project}/build/",
            f"{self.config.local_project}/build/"
        ]

        result = subprocess.run(rsync_args, capture_output=True, text=True)
        if result.returncode == 0:
            print("  Done")
            return True
        print(f"  Fetch failed: {result.stderr}")
        return False

    def start_build(self, incremental: bool = True) -> bool:
        """Start remote build (non-blocking)."""
        if self.build_thread and self.build_thread.is_alive():
            print("Build already in progress")
            return False

        self.build_status = "starting"
        self.build_log = []

        self.build_thread = threading.Thread(
            target=self._build_worker,
            args=(incremental,),
            daemon=True
        )
        self.build_thread.start()
        return True

    def _build_worker(self, incremental: bool):
        """Background build worker."""
        self.build_status = "syncing"

        # Sync sources
        if not self.sync_to_remote():
            self.build_status = "sync_failed"
            return

        self.build_status = "building"
        print("\nStarting remote Vivado build...")

        # Build command
        build_script = "incremental_build.tcl" if incremental else "full_build.tcl"
        cmd = f"""
cd {self.config.remote_project}/build && \
{self.config.vivado_path} -mode batch -source {build_script} 2>&1
"""

        start = time.time()

        # Stream output
        process = subprocess.Popen(
            ["ssh", "-p", str(self.config.port), self.config.ssh_target, cmd],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True
        )

        for line in process.stdout:
            line = line.rstrip()
            self.build_log.append(line)

            # Print progress indicators
            if "Phase " in line or "Finished" in line or "ERROR" in line:
                print(f"  {line}")

        process.wait()
        elapsed = time.time() - start

        if process.returncode == 0:
            self.build_status = "success"
            print(f"\nBuild complete in {elapsed/60:.1f} minutes")

            # Fetch bitstream
            self.sync_from_remote("*.bit")
        else:
            self.build_status = "failed"
            print(f"\nBuild failed after {elapsed/60:.1f} minutes")
            print("Last 20 lines of log:")
            for line in self.build_log[-20:]:
                print(f"  {line}")

    def wait_for_build(self, timeout: float = None) -> bool:
        """Wait for build to complete."""
        if self.build_thread:
            self.build_thread.join(timeout=timeout)
            return self.build_status == "success"
        return False

    def get_status(self) -> dict:
        """Get current build status."""
        return {
            "status": self.build_status,
            "log_lines": len(self.build_log),
            "is_building": self.build_thread and self.build_thread.is_alive()
        }


#==============================================================================
# File Watcher for Auto-Sync
#==============================================================================

class FileWatcher:
    """Watch for local changes and auto-sync."""

    def __init__(self, builder: RemoteBuilder):
        self.builder = builder
        self.running = False
        self.last_sync = 0
        self.sync_delay = 2.0  # Debounce delay

    def get_mtime(self) -> float:
        """Get latest modification time of RTL files."""
        latest = 0
        rtl_dir = self.builder.config.local_project / "rtl"

        for f in rtl_dir.rglob("*.v"):
            mtime = f.stat().st_mtime
            if mtime > latest:
                latest = mtime

        for f in rtl_dir.rglob("*.sv"):
            mtime = f.stat().st_mtime
            if mtime > latest:
                latest = mtime

        return latest

    def watch(self):
        """Watch for changes and sync."""
        print("Watching for changes (Ctrl+C to stop)...")
        self.running = True
        last_mtime = self.get_mtime()

        try:
            while self.running:
                current_mtime = self.get_mtime()

                if current_mtime > last_mtime:
                    print("\nChanges detected, syncing...")
                    time.sleep(self.sync_delay)  # Debounce
                    self.builder.sync_to_remote()
                    last_mtime = self.get_mtime()

                time.sleep(1.0)

        except KeyboardInterrupt:
            print("\nStopped watching")
            self.running = False


#==============================================================================
# Setup Wizard
#==============================================================================

def setup_wizard() -> RemoteConfig:
    """Interactive setup for remote build configuration."""
    print("\n" + "="*60)
    print("FluxRipper Remote Build Setup")
    print("="*60)
    print()
    print("This will configure a remote Linux server for Vivado builds.")
    print("You'll need SSH access to an x86_64 Linux machine with Vivado.")
    print()

    config = RemoteConfig()

    # Host
    print("SSH Host Configuration")
    print("-" * 40)
    host = input(f"SSH host (or ~/.ssh/config alias) [{config.host}]: ").strip()
    if host:
        config.host = host

    user = input(f"SSH user (leave empty if in ssh config) [{config.user}]: ").strip()
    if user:
        config.user = user

    port = input(f"SSH port [{config.port}]: ").strip()
    if port:
        config.port = int(port)

    # Test connection
    print()
    builder = RemoteBuilder(config)
    if not builder.check_connection():
        print("\nFailed to connect. Please check your SSH configuration.")
        print("Tips:")
        print("  1. Add host to ~/.ssh/config for easier access")
        print("  2. Set up SSH key authentication")
        print("  3. Test with: ssh", config.ssh_target)
        return None

    # Vivado path
    print()
    print("Vivado Configuration")
    print("-" * 40)
    vivado = input(f"Vivado path [{config.vivado_path}]: ").strip()
    if vivado:
        config.vivado_path = vivado

    if not builder.check_vivado():
        print("\nVivado not found. Please check the path.")
        alt = input("Try alternate path? [/tools/Xilinx/Vivado/2024.1/bin/vivado]: ").strip()
        if alt:
            config.vivado_path = alt

    # Remote project path
    print()
    print("Project Configuration")
    print("-" * 40)
    remote = input(f"Remote project path [{config.remote_project}]: ").strip()
    if remote:
        config.remote_project = remote

    # Save config
    config_file = config.local_project / "tools" / "devloop" / "remote_config.json"
    config.save_to_file(config_file)
    print(f"\nConfiguration saved to {config_file}")

    return config


#==============================================================================
# CLI
#==============================================================================

def main():
    parser = argparse.ArgumentParser(description="FluxRipper Remote Build")
    parser.add_argument("command", nargs="?", default="status",
                       choices=["setup", "status", "sync", "build", "fetch", "watch"],
                       help="Command to run")
    parser.add_argument("--full", action="store_true",
                       help="Force full build (not incremental)")

    args = parser.parse_args()

    # Load or create config
    config = RemoteConfig()
    config_file = config.local_project / "tools" / "devloop" / "remote_config.json"

    if args.command == "setup":
        setup_wizard()
        return

    if config_file.exists():
        config.load_from_file(config_file)
    else:
        print("No configuration found. Run 'remote_build.py setup' first.")
        print()
        print("Or create remote_config.json with:")
        print(json.dumps({
            "host": "your-build-server",
            "user": "username",
            "remote_project": "~/FluxRipper",
            "vivado_path": "/opt/Xilinx/Vivado/2024.1/bin/vivado"
        }, indent=2))
        sys.exit(1)

    builder = RemoteBuilder(config)

    if args.command == "status":
        if not builder.check_connection():
            sys.exit(1)
        builder.check_vivado()

        # Check for existing builds
        result = builder.ssh_cmd(
            f"ls -la {config.remote_project}/build/*.bit 2>/dev/null || echo 'No bitstreams'"
        )
        print(f"\nRemote bitstreams:")
        print(result.stdout)

    elif args.command == "sync":
        if not builder.sync_to_remote():
            sys.exit(1)

    elif args.command == "build":
        print("Starting remote build...")
        builder.start_build(incremental=not args.full)
        success = builder.wait_for_build(timeout=3600)  # 1 hour max
        sys.exit(0 if success else 1)

    elif args.command == "fetch":
        if not builder.sync_from_remote("*.bit"):
            sys.exit(1)

    elif args.command == "watch":
        watcher = FileWatcher(builder)
        watcher.watch()


if __name__ == "__main__":
    main()
