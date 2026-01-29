import argparse
import os
import subprocess
from pathlib import Path
from typing import List, Optional

import yaml


def run_config(executable, config_path):
    command = [executable, config_path]
    print(f"Running: {' '.join(command)}")
    try:
        subprocess.run(command, check=True)
        print(f"Finished running {config_path}")
    except subprocess.CalledProcessError as e:
        print(f"Error running {config_path}: {e}")
    print("-" * 50)


def parse_config(config_path: Path) -> Optional[dict]:
    try:
        with open(config_path, "r", encoding="utf-8") as stream:
            return yaml.safe_load(stream) or {}
    except Exception as exc:
        print(f"Failed to parse {config_path}: {exc}")
        return None


def build_required_paths(config: dict) -> List[Path]:
    reader = config.get("READER", {})
    input_dir = reader.get("input_dir")
    if not input_dir:
        return []

    base_path = Path(input_dir)
    required = [base_path]
    for key in ("image_path", "pose_path", "depth_path"):
        sub_path = reader.get(key)
        if sub_path:
            required.append(base_path / sub_path)
    return required


def missing_paths(paths: List[Path]) -> List[Path]:
    return [path for path in paths if not path.exists()]


def process_configs(executable, folder, *, skip_missing_data: bool, dry_run: bool, max_configs: Optional[int]):
    configs_run = 0
    for root, dirs, files in os.walk(folder):
        for file in sorted(files):
            if not file.endswith(".yaml"):
                continue

            config_path = Path(root) / file
            config_data = parse_config(config_path)
            if config_data is None:
                continue

            required = build_required_paths(config_data)
            missing = missing_paths(required)

            print("I AM HER EBITCH")
            if missing and skip_missing_data:
                missing_str = ", ".join(str(p) for p in missing)
                print(f"Skipping {config_path}: missing {missing_str}")
                continue

            if dry_run:
                print(f"[dry-run] {' '.join([executable, str(config_path)])}")
            else:
                run_config(executable, str(config_path))

            configs_run += 1
            if max_configs is not None and configs_run >= max_configs:
                print(f"Reached max-configs limit ({max_configs}).")
                return


def main():
    parser = argparse.ArgumentParser(description="Process YAML configurations.")
    parser.add_argument(
        "--executable",
        type=str,
        default="./build/slam_trainer",
        help="Path to the executable (default: ./build/slam_trainer)",
    )
    parser.add_argument(
        "--config-dir",
        type=str,
        required=True,
        help="Root folder of configuration files",
    )
    parser.add_argument(
        "--skip-missing-data",
        dest="skip_missing_data",
        action="store_true",
        default=True,
        help="Skip configs whose expected data folders are absent (default: on)",
    )
    parser.add_argument(
        "--no-skip-missing-data",
        dest="skip_missing_data",
        action="store_false",
        help="Attempt to run configs even if their data folders are missing",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Only print the commands that would be executed",
    )
    parser.add_argument(
        "--max-configs",
        type=int,
        help="Optional limit on the number of configs to run",
    )

    args = parser.parse_args()

    executable = args.executable
    config_root_folder = args.config_dir
    printable_root = config_root_folder
    print(
        f"Starting to process all YAML files in {printable_root} and its subfolders."
    )
    process_configs(
        executable,
        config_root_folder,
        skip_missing_data=args.skip_missing_data,
        dry_run=args.dry_run,
        max_configs=args.max_configs,
    )
    print("All configurations have been processed.")


if __name__ == "__main__":
    main()
