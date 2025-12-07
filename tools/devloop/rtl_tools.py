#!/usr/bin/env python3
"""
FluxRipper RTL Development Tools

Fast RTL iteration using simulation and incremental builds.

Created: 2025-12-07 16:55
License: BSD-3-Clause
"""

import subprocess
import time
import os
import sys
from pathlib import Path
from dataclasses import dataclass
from typing import List, Optional, Dict
import hashlib
import json

#==============================================================================
# Configuration
#==============================================================================

@dataclass
class RTLConfig:
    """RTL build configuration."""
    project_root: Path = Path(__file__).parent.parent.parent
    rtl_dir: Path = None
    sim_dir: Path = None
    build_dir: Path = None

    # Tools
    iverilog_path: str = "iverilog"
    vvp_path: str = "vvp"
    vivado_path: str = "/opt/Xilinx/Vivado/2024.1/bin/vivado"

    # Incremental build
    use_incremental: bool = True
    reference_checkpoint: str = "previous_routed.dcp"

    def __post_init__(self):
        self.rtl_dir = self.project_root / "rtl"
        self.sim_dir = self.project_root / "sim"
        self.build_dir = self.project_root / "build"


#==============================================================================
# RTL Module Tracking
#==============================================================================

@dataclass
class RTLModule:
    """Represents an RTL module for dependency tracking."""
    name: str
    path: Path
    dependencies: List[str]
    hash: str


def get_module_hash(path: Path) -> str:
    """Calculate hash of a Verilog file."""
    return hashlib.sha256(path.read_bytes()).hexdigest()[:16]


def find_dependencies(path: Path) -> List[str]:
    """Extract module instantiations from Verilog file."""
    deps = []
    content = path.read_text()

    # Simple regex-free parsing for module instantiations
    # Looks for: module_name instance_name (
    lines = content.split('\n')
    for line in lines:
        line = line.strip()
        # Skip comments and preprocessor
        if line.startswith('//') or line.startswith('`'):
            continue
        # Look for instantiation pattern
        if '(' in line and not line.startswith('module') and not line.startswith('function'):
            parts = line.split()
            if len(parts) >= 2 and not parts[0] in ['if', 'else', 'case', 'for', 'while', 'assign', 'always', 'initial']:
                # First word might be module name
                module_name = parts[0]
                if module_name and module_name[0].isalpha():
                    deps.append(module_name)

    return list(set(deps))


def scan_rtl_modules(rtl_dir: Path) -> Dict[str, RTLModule]:
    """Scan all RTL modules and their dependencies."""
    modules = {}

    for vfile in rtl_dir.rglob("*.v"):
        name = vfile.stem
        modules[name] = RTLModule(
            name=name,
            path=vfile,
            dependencies=find_dependencies(vfile),
            hash=get_module_hash(vfile)
        )

    for svfile in rtl_dir.rglob("*.sv"):
        name = svfile.stem
        modules[name] = RTLModule(
            name=name,
            path=svfile,
            dependencies=find_dependencies(svfile),
            hash=get_module_hash(svfile)
        )

    return modules


def get_changed_modules(modules: Dict[str, RTLModule], cache_file: Path) -> List[str]:
    """Determine which modules changed since last build."""
    changed = []

    # Load previous hashes
    prev_hashes = {}
    if cache_file.exists():
        prev_hashes = json.loads(cache_file.read_text())

    # Compare
    for name, module in modules.items():
        if name not in prev_hashes or prev_hashes[name] != module.hash:
            changed.append(name)

    return changed


def save_module_cache(modules: Dict[str, RTLModule], cache_file: Path):
    """Save module hashes for incremental build."""
    hashes = {name: mod.hash for name, mod in modules.items()}
    cache_file.write_text(json.dumps(hashes, indent=2))


#==============================================================================
# Simulation
#==============================================================================

class Simulator:
    """Icarus Verilog based RTL simulation."""

    def __init__(self, config: RTLConfig):
        self.config = config

    def compile(self, top_module: str, sources: List[Path],
                output: Path = None) -> bool:
        """Compile Verilog sources."""
        if output is None:
            output = self.config.sim_dir / f"{top_module}.vvp"

        output.parent.mkdir(parents=True, exist_ok=True)

        cmd = [
            self.config.iverilog_path,
            "-g2012",  # SystemVerilog support
            "-o", str(output),
            "-s", top_module,  # Top module
        ]

        # Add include paths
        cmd.extend(["-I", str(self.config.rtl_dir)])

        # Add sources
        cmd.extend(str(s) for s in sources)

        print(f"Compiling {top_module}...")
        start = time.time()

        result = subprocess.run(cmd, capture_output=True)
        elapsed = time.time() - start

        if result.returncode != 0:
            print(f"Compilation failed ({elapsed:.1f}s):")
            print(result.stderr.decode())
            return False

        print(f"Compiled in {elapsed:.1f}s")
        return True

    def run(self, vvp_file: Path, timeout: float = 60.0) -> Optional[str]:
        """Run simulation and return output."""
        print(f"Running simulation...")
        start = time.time()

        try:
            result = subprocess.run(
                [self.config.vvp_path, str(vvp_file)],
                capture_output=True,
                timeout=timeout
            )
            elapsed = time.time() - start

            output = result.stdout.decode()

            if result.returncode != 0:
                print(f"Simulation failed ({elapsed:.1f}s):")
                print(result.stderr.decode())
                return None

            print(f"Simulation complete in {elapsed:.1f}s")
            return output

        except subprocess.TimeoutExpired:
            print(f"Simulation timed out after {timeout}s")
            return None

    def simulate(self, top_module: str, sources: List[Path]) -> Optional[str]:
        """Compile and run simulation."""
        vvp_file = self.config.sim_dir / f"{top_module}.vvp"

        if not self.compile(top_module, sources, vvp_file):
            return None

        return self.run(vvp_file)

    def check_assertions(self, output: str) -> bool:
        """Check simulation output for assertion failures."""
        if output is None:
            return False

        # Check for common failure indicators
        failure_indicators = [
            "ASSERTION FAILED",
            "ERROR:",
            "FAIL:",
            "*** FAILED ***",
            "$fatal",
        ]

        for indicator in failure_indicators:
            if indicator in output:
                return False

        # Check for pass indicators
        pass_indicators = [
            "PASS",
            "All tests passed",
            "SUCCESS",
        ]

        for indicator in pass_indicators:
            if indicator in output:
                return True

        # No explicit pass/fail - assume pass if no errors
        return True


#==============================================================================
# Incremental Vivado Build
#==============================================================================

class VivadoBuilder:
    """Vivado incremental synthesis and implementation."""

    def __init__(self, config: RTLConfig):
        self.config = config

    def generate_incremental_tcl(self, changed_modules: List[str]) -> Path:
        """Generate TCL script for incremental build."""
        tcl_path = self.config.build_dir / "incremental_build.tcl"

        reference_dcp = self.config.build_dir / self.config.reference_checkpoint
        use_incremental = reference_dcp.exists() and self.config.use_incremental

        tcl_content = f'''
# FluxRipper Incremental Build
# Generated: {time.strftime("%Y-%m-%d %H:%M:%S")}
# Changed modules: {", ".join(changed_modules) if changed_modules else "None (full build)"}

set project_dir "{self.config.build_dir}"
set rtl_dir "{self.config.rtl_dir}"

# Open project
open_project $project_dir/fluxripper.xpr

# Update changed sources
update_compile_order -fileset sources_1

'''

        if use_incremental and len(changed_modules) < 10:
            # Incremental build
            tcl_content += f'''
# Incremental synthesis - reuse previous results
puts "Using incremental build (reference: {self.config.reference_checkpoint})"
set_property INCREMENTAL_CHECKPOINT {reference_dcp} [current_run synth_1]
set_property INCREMENTAL_CHECKPOINT {reference_dcp} [current_run impl_1]

# Run synthesis (incremental)
reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1

# Run implementation (incremental)
launch_runs impl_1 -jobs 4
wait_on_run impl_1

'''
        else:
            # Full build
            tcl_content += '''
# Full build (too many changes for incremental)
puts "Running full build"

reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1

reset_run impl_1
launch_runs impl_1 -jobs 4
wait_on_run impl_1

'''

        tcl_content += f'''
# Generate bitstream
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

# Save checkpoint for next incremental build
file copy -force $project_dir/fluxripper.runs/impl_1/fluxripper_wrapper.dcp \\
    $project_dir/{self.config.reference_checkpoint}

# Report timing
open_run impl_1
report_timing_summary -file $project_dir/timing_summary.rpt

puts "Build complete"
close_project
'''

        tcl_path.write_text(tcl_content)
        return tcl_path

    def build(self, changed_modules: List[str] = None) -> bool:
        """Run Vivado build."""
        tcl_path = self.generate_incremental_tcl(changed_modules or [])

        print(f"Starting Vivado build...")
        if changed_modules:
            print(f"  Changed modules: {', '.join(changed_modules)}")

        start = time.time()

        result = subprocess.run(
            [self.config.vivado_path, "-mode", "batch", "-source", str(tcl_path)],
            cwd=self.config.build_dir,
            capture_output=True
        )

        elapsed = time.time() - start

        if result.returncode != 0:
            print(f"Build failed after {elapsed/60:.1f} minutes")
            # Show last 50 lines of log
            log_lines = result.stdout.decode().split('\n')[-50:]
            print('\n'.join(log_lines))
            return False

        print(f"Build complete in {elapsed/60:.1f} minutes")
        return True

    def estimate_build_time(self, changed_modules: List[str]) -> str:
        """Estimate build time based on changes."""
        reference_exists = (self.config.build_dir / self.config.reference_checkpoint).exists()

        if not reference_exists:
            return "~15-20 minutes (full build, no reference)"
        elif len(changed_modules) == 0:
            return "~1-2 minutes (no changes, verification only)"
        elif len(changed_modules) <= 3:
            return "~2-4 minutes (incremental, few changes)"
        elif len(changed_modules) <= 10:
            return "~5-8 minutes (incremental, moderate changes)"
        else:
            return "~12-15 minutes (too many changes, near-full build)"


#==============================================================================
# Unified RTL Workflow
#==============================================================================

class RTLWorkflow:
    """Unified RTL development workflow."""

    def __init__(self, config: RTLConfig = None):
        self.config = config or RTLConfig()
        self.simulator = Simulator(self.config)
        self.builder = VivadoBuilder(self.config)
        self.cache_file = self.config.build_dir / ".rtl_cache.json"

    def quick_check(self, module: str) -> bool:
        """Quick simulation check of a module."""
        # Find module and its testbench
        module_path = None
        for vfile in self.config.rtl_dir.rglob(f"{module}.v"):
            module_path = vfile
            break

        if not module_path:
            print(f"Module {module} not found")
            return False

        # Look for testbench
        tb_path = self.config.sim_dir / f"tb_{module}.v"
        if not tb_path.exists():
            tb_path = self.config.rtl_dir.parent / "tb" / f"tb_{module}.v"

        if not tb_path.exists():
            print(f"No testbench found for {module}")
            return False

        # Gather all dependencies
        sources = list(self.config.rtl_dir.rglob("*.v"))
        sources.append(tb_path)

        # Simulate
        output = self.simulator.simulate(f"tb_{module}", sources)
        return self.simulator.check_assertions(output)

    def simulate_all(self) -> Dict[str, bool]:
        """Run all testbenches."""
        results = {}

        # Find all testbenches
        tb_dirs = [
            self.config.sim_dir,
            self.config.rtl_dir.parent / "tb"
        ]

        for tb_dir in tb_dirs:
            if not tb_dir.exists():
                continue

            for tb_file in tb_dir.glob("tb_*.v"):
                module = tb_file.stem[3:]  # Remove "tb_" prefix
                print(f"\n{'='*60}")
                print(f"Testing: {module}")
                print('='*60)

                sources = list(self.config.rtl_dir.rglob("*.v"))
                sources.append(tb_file)

                output = self.simulator.simulate(tb_file.stem, sources)
                results[module] = self.simulator.check_assertions(output)

        return results

    def smart_build(self) -> bool:
        """Build with automatic incremental detection."""
        # Scan modules
        modules = scan_rtl_modules(self.config.rtl_dir)
        changed = get_changed_modules(modules, self.cache_file)

        print(f"\nRTL Build Analysis:")
        print(f"  Total modules: {len(modules)}")
        print(f"  Changed: {len(changed)}")
        print(f"  Estimate: {self.builder.estimate_build_time(changed)}")

        if len(changed) == 0:
            print("No changes detected, skipping build")
            return True

        # Run simulations first for changed modules
        print("\nRunning simulations for changed modules...")
        for module in changed:
            if not self.quick_check(module):
                print(f"Simulation failed for {module}, aborting build")
                return False

        # Build
        success = self.builder.build(changed)

        if success:
            # Update cache
            save_module_cache(modules, self.cache_file)

        return success

    def status(self):
        """Show RTL build status."""
        modules = scan_rtl_modules(self.config.rtl_dir)
        changed = get_changed_modules(modules, self.cache_file)

        print(f"\nRTL Status:")
        print(f"  Modules: {len(modules)}")
        print(f"  Changed since last build: {len(changed)}")

        if changed:
            print(f"\n  Changed modules:")
            for name in changed[:10]:
                print(f"    - {name}")
            if len(changed) > 10:
                print(f"    ... and {len(changed)-10} more")

        print(f"\n  Build estimate: {self.builder.estimate_build_time(changed)}")

        ref_dcp = self.config.build_dir / self.config.reference_checkpoint
        if ref_dcp.exists():
            mtime = time.ctime(ref_dcp.stat().st_mtime)
            print(f"  Last build: {mtime}")
        else:
            print(f"  Last build: Never (full build required)")


#==============================================================================
# CLI
#==============================================================================

def main():
    import argparse

    parser = argparse.ArgumentParser(description="FluxRipper RTL Tools")
    parser.add_argument("command", choices=["status", "sim", "build", "check"],
                       help="Command to run")
    parser.add_argument("--module", "-m", help="Specific module to test")

    args = parser.parse_args()

    workflow = RTLWorkflow()

    if args.command == "status":
        workflow.status()

    elif args.command == "sim":
        if args.module:
            success = workflow.quick_check(args.module)
        else:
            results = workflow.simulate_all()
            passed = sum(1 for v in results.values() if v)
            print(f"\nResults: {passed}/{len(results)} passed")
            success = all(results.values())
        sys.exit(0 if success else 1)

    elif args.command == "build":
        success = workflow.smart_build()
        sys.exit(0 if success else 1)

    elif args.command == "check":
        if args.module:
            success = workflow.quick_check(args.module)
            sys.exit(0 if success else 1)
        else:
            print("--module required for check command")
            sys.exit(1)


if __name__ == "__main__":
    main()
