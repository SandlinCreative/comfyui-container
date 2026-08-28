#!/usr/bin/env python3
"""Combine requirements.txt files found below a directory."""

from __future__ import annotations

import argparse
import re
from dataclasses import dataclass
from pathlib import Path

try:
    from packaging.requirements import InvalidRequirement, Requirement
    from packaging.utils import canonicalize_name
    from packaging.version import InvalidVersion, Version
except ImportError as exc:  # pragma: no cover - depends on the Python environment
    raise SystemExit(
        "This script requires the 'packaging' module. Install it with "
        "'python -m pip install packaging'."
    ) from exc


INLINE_COMMENT = re.compile(r"\s+#.*$")
LOWER_BOUND_OPERATORS = {"==", "===", ">=", ">", "~="}


@dataclass
class SelectedRequirement:
    line: str
    minimum_version: Version | None


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Recursively combine requirements.txt files, keeping the requirement "
            "with the highest minimum version when duplicates are found."
        )
    )
    parser.add_argument("directory", type=Path, help="directory to search")
    parser.add_argument(
        "-o",
        "--output",
        type=Path,
        default=Path("combined_requirements.txt"),
        help="output file (default: ./combined_requirements.txt)",
    )
    return parser.parse_args()


def logical_lines(path: Path):
    """Yield non-empty requirement lines, joining pip-style continuations."""
    pending = ""
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue

        line = INLINE_COMMENT.sub("", line).strip()
        if not line:
            continue

        if line.endswith("\\"):
            pending += line[:-1].rstrip() + " "
            continue

        yield (pending + line).strip()
        pending = ""

    if pending:
        yield pending.strip()


def minimum_version(requirement: Requirement) -> Version | None:
    """Return the highest exact/lower-bound version in a requirement."""
    versions = []
    for specifier in requirement.specifier:
        if specifier.operator not in LOWER_BOUND_OPERATORS:
            continue

        version_text = specifier.version.removesuffix(".*")
        try:
            versions.append(Version(version_text))
        except InvalidVersion:
            continue

    return max(versions, default=None)


def requirement_key(requirement: Requirement) -> tuple[str, tuple[str, ...], str]:
    """Identify requirements without collapsing different extras or markers."""
    extras = tuple(sorted(canonicalize_name(extra) for extra in requirement.extras))
    marker = str(requirement.marker) if requirement.marker else ""
    return canonicalize_name(requirement.name), extras, marker


def combine_requirements(directory: Path, output: Path) -> tuple[int, int]:
    files = sorted(
        path
        for path in directory.rglob("requirements.txt")
        if path.is_file() and path.resolve() != output
    )

    selected: dict[
        tuple[str, tuple[str, ...], str], SelectedRequirement
    ] = {}
    passthrough_lines: dict[str, None] = {}

    for path in files:
        for line in logical_lines(path):
            try:
                requirement = Requirement(line)
            except InvalidRequirement:
                # Preserve pip options, VCS URLs, and other non-PEP 508 lines once.
                passthrough_lines.setdefault(line, None)
                continue

            key = requirement_key(requirement)
            candidate = SelectedRequirement(line, minimum_version(requirement))
            current = selected.get(key)
            if current is None or (
                candidate.minimum_version is not None
                and (
                    current.minimum_version is None
                    or candidate.minimum_version > current.minimum_version
                )
            ):
                selected[key] = candidate

    lines = [item.line for item in selected.values()]
    lines.extend(passthrough_lines)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text("\n".join(lines) + ("\n" if lines else ""), encoding="utf-8")
    return len(files), len(lines)


def main() -> None:
    args = parse_args()
    directory = args.directory.expanduser().resolve()
    output = args.output.expanduser().resolve()

    if not directory.is_dir():
        raise SystemExit(f"Not a directory: {directory}")

    file_count, requirement_count = combine_requirements(directory, output)
    print(
        f"Combined {file_count} requirements.txt file(s) into {output} "
        f"({requirement_count} unique requirement(s))."
    )


if __name__ == "__main__":
    main()
