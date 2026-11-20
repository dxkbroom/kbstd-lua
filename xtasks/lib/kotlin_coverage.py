"""Shared parser and report model for the kotlinx.coroutines test ports."""

from __future__ import annotations

import re
import subprocess
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable

KOTLIN_REF = re.compile(r"^\s*-- kotlin:\s*(\S+)@(\S+)\s*$")
DESCRIBE = re.compile(r'^\s*describe\(\s*"([^"]+)"')
TEST = re.compile(r'\b(it|pending)\(\s*"([^"]+)"')
MARK = re.compile(r"^\s*--\s*(adapted|n/a|todo):\s*(.*)$")
COMMENT = re.compile(r"^\s*--(.*)$")
KOTLIN_TEST = re.compile(
    r"@Test\b[^\n]*\n(?:\s*@[^\n]*\n|\s*//[^\n]*\n|\s*/\*.*?\*/\s*\n)*\s*"
    r"(?:(?:public|internal|private|open|abstract|override|suspend)\s+)*fun\s+`?(\w+)",
    re.S,
)
STATUSES = ("ported", "adapted", "n/a", "todo", "missing")


@dataclass(frozen=True)
class TestPort:
    name: str
    status: str
    reason: str
    line: int


@dataclass
class Port:
    cls: str
    path: str
    tag: str
    file: Path
    tests: list[TestPort] = field(default_factory=list)


@dataclass(frozen=True)
class Issue:
    code: str
    message: str
    file: str | None = None
    cls: str | None = None
    test: str | None = None

    def as_dict(self) -> dict[str, str]:
        result = {"code": self.code, "message": self.message}
        if self.file is not None:
            result["file"] = self.file
        if self.cls is not None:
            result["class"] = self.cls
        if self.test is not None:
            result["test"] = self.test
        return result


def reason_above(lines: list[str], index: int) -> tuple[str, str] | None:
    """Find a status mark in the contiguous comment block above a test."""
    block: list[str] = []
    cursor = index - 1
    while cursor >= 0 and COMMENT.match(lines[cursor]):
        block.insert(0, lines[cursor])
        cursor -= 1
    for mark_index, line in enumerate(block):
        mark = MARK.match(line)
        if mark:
            text = [mark.group(2).strip()]
            for more in block[mark_index + 1 :]:
                if MARK.match(more):
                    break
                text.append(COMMENT.match(more).group(1).strip())
            return mark.group(1), " ".join(part for part in text if part)
    return None


def parse_port(file: Path) -> tuple[list[Port], list[Issue]]:
    """Parse port classes and return structural issues without losing duplicates."""
    try:
        lines = file.read_text().splitlines()
    except OSError as error:
        return [], [Issue("port-unreadable", str(error), file=str(file))]

    ports: list[Port] = []
    issues: list[Issue] = []
    pending_ref: re.Match[str] | None = None
    current: Port | None = None
    saw_ref = False
    saw_describe = False
    for index, line in enumerate(lines):
        ref = KOTLIN_REF.match(line)
        if ref:
            pending_ref = ref
            saw_ref = True
            continue
        describe = DESCRIBE.match(line)
        if describe and pending_ref:
            current = Port(describe.group(1), pending_ref.group(1), pending_ref.group(2), file)
            ports.append(current)
            pending_ref = None
            saw_describe = True
            continue
        if current is None:
            continue
        # luafmt may put the name in the line immediately following `it(`.
        text = line if TEST.search(line) else line + (lines[index + 1] if index + 1 < len(lines) else "")
        test = TEST.search(text)
        if not test or not re.match(r"^\s*(it|pending)\(", line):
            continue
        kind, name = test.groups()
        mark = reason_above(lines, index)
        if kind == "pending":
            if mark and mark[0] in ("n/a", "todo"):
                status, reason = mark
            else:
                status, reason = "todo", ""
        elif mark and mark[0] == "adapted":
            status, reason = mark
        else:
            status, reason = "ported", ""
            if mark and mark[0] in ("n/a", "todo"):
                issues.append(Issue(
                    "invalid-status-marker",
                    f"{mark[0]} marker is attached to an active test",
                    file=str(file), cls=current.cls, test=name,
                ))
        current.tests.append(TestPort(name, status, reason, index + 1))

    if not saw_ref:
        issues.append(Issue("kotlin-reference-missing", "no Kotlin source reference", file=str(file)))
    elif not saw_describe:
        issues.append(Issue("describe-missing", "Kotlin reference is not followed by a describe block", file=str(file)))
    if pending_ref is not None:
        issues.append(Issue("describe-missing", "Kotlin reference is not followed by a describe block", file=str(file)))
    return ports, issues


def kotlin_source(path: str, tag: str, checkout: Path) -> str | None:
    cdtag_source = checkout / ".git" / "cdtag" / tag / path
    if cdtag_source.is_file():
        try:
            return cdtag_source.read_text()
        except OSError:
            pass
    try:
        return subprocess.run(
            ["git", "-C", str(checkout), "show", f"{tag}:{path}"],
            check=True,
            capture_output=True,
            text=True,
        ).stdout
    except (OSError, subprocess.CalledProcessError):
        return None


def relative(path: Path, root: Path) -> str:
    try:
        return path.resolve().relative_to(root.resolve()).as_posix()
    except ValueError:
        return str(path)


def build_report(
    files: list[Path],
    root: Path,
    checkout: Path,
    source_loader: Callable[[str, str, Path], str | None] = kotlin_source,
) -> dict[str, object]:
    """Create the JSON-ready coverage report and its validation issues."""
    classes: list[dict[str, object]] = []
    issues: list[Issue] = []
    seen_classes: dict[str, str] = {}

    for file in sorted(files):
        parsed, parse_issues = parse_port(file)
        issues.extend(
            Issue(issue.code, issue.message, file=relative(file, root), cls=issue.cls, test=issue.test)
            for issue in parse_issues
        )
        if not parsed:
            continue
        for port in parsed:
            lua_file = relative(file, root)
            if port.cls in seen_classes:
                issues.append(Issue(
                    "duplicate-class-port",
                    f"class also appears in {seen_classes[port.cls]}",
                    file=lua_file,
                    cls=port.cls,
                ))
            else:
                seen_classes[port.cls] = lua_file

            source = source_loader(port.path, port.tag, checkout)
            source_tests: list[str] = []
            if source is None:
                issues.append(Issue(
                    "kotlin-source-unresolved",
                    f"cannot read {port.path}@{port.tag} from {checkout}",
                    file=lua_file,
                    cls=port.cls,
                ))
            else:
                if not re.search(rf"\bclass\s+{re.escape(port.cls)}\b", source):
                    issues.append(Issue(
                        "kotlin-class-missing",
                        f"class {port.cls} was not found in {port.path}",
                        file=lua_file,
                        cls=port.cls,
                    ))
                source_tests = KOTLIN_TEST.findall(source)

            mapped: dict[str, TestPort] = {}
            for test in port.tests:
                if test.name in mapped:
                    issues.append(Issue(
                        "duplicate-test-mapping",
                        f"test is listed more than once (first at line {mapped[test.name].line})",
                        file=lua_file,
                        cls=port.cls,
                        test=test.name,
                    ))
                mapped[test.name] = test
                if not test.reason and test.status in ("adapted", "n/a", "todo"):
                    issues.append(Issue(
                        "status-reason-missing",
                        f"{test.status} status requires a reason",
                        file=lua_file,
                        cls=port.cls,
                        test=test.name,
                    ))

            stale_tests = [
                {"name": name, "line": test.line}
                for name, test in mapped.items()
                if source is not None and name not in source_tests
            ]
            for stale in stale_tests:
                issues.append(Issue(
                    "stale-test-mapping",
                    f"{stale['name']} is not a Kotlin @Test in {port.cls}",
                    file=lua_file,
                    cls=port.cls,
                    test=str(stale["name"]),
                ))

            tests: list[dict[str, object]] = []
            names = source_tests if source is not None else [test.name for test in port.tests]
            for name in names:
                test = mapped.get(name)
                tests.append({
                    "name": name,
                    "status": test.status if test else "missing",
                    "reason": test.reason or None if test else None,
                })
            counts = {status: sum(item["status"] == status for item in tests) for status in STATUSES}
            classes.append({
                "name": port.cls,
                "kotlin_source": port.path,
                "tag": port.tag,
                "lua_port": lua_file,
                "tests": tests,
                "stale_tests": stale_tests,
                "counts": counts,
            })

    totals = {status: 0 for status in STATUSES}
    for item in classes:
        for status in STATUSES:
            totals[status] += item["counts"][status]  # type: ignore[index]
    summary = {"classes": len(classes), **totals, "issues": len(issues)}
    summary["n_a"] = summary.pop("n/a")
    for item in classes:
        item["counts"]["n_a"] = item["counts"].pop("n/a")  # type: ignore[index]
    return {
        "schema_version": 1,
        "summary": summary,
        "classes": classes,
        "issues": [issue.as_dict() for issue in issues],
    }


def markdown_report(report: dict[str, object]) -> str:
    """Render a portable nested Markdown list from the report model."""
    summary = report["summary"]
    counts = " · ".join(
        f"{summary[key]} {label}"
        for key, label in (("ported", "ported"), ("adapted", "adapted"), ("n_a", "n/a"), ("todo", "todo"), ("missing", "missing"))
    )
    lines = [f"# Kotlin coroutine test ports — {summary['classes']} classes", "", f"{counts}", ""]
    status_icon = {"ported": "✓", "adapted": "~", "n/a": "○", "todo": "·", "missing": "✗"}
    for cls in report["classes"]:
        class_counts = " · ".join(
            f"{cls['counts'][key]} {label}"
            for key, label in (("ported", "ported"), ("adapted", "adapted"), ("n_a", "n/a"), ("todo", "todo"), ("missing", "missing"))
            if cls["counts"][key]
        )
        lines.append(f"- **{cls['name']}** — `{cls['kotlin_source']}@{cls['tag']}` → `{cls['lua_port']}` ({class_counts})")
        for test in cls["tests"]:
            suffix = f" — {test['reason']}" if test["reason"] else ""
            lines.append(f"  - {status_icon[test['status']]} `{test['name']}` — {test['status']}{suffix}")
        for stale in cls["stale_tests"]:
            lines.append(f"  - ✗ `{stale['name']}` — stale mapping (Lua line {stale['line']})")
    if report["issues"]:
        lines.extend(("", "## Issues"))
        for issue in report["issues"]:
            location = ":".join(part for part in (issue.get("file"), issue.get("class"), issue.get("test")) if part)
            lines.append(f"- `{issue['code']}`{f' at `{location}`' if location else ''}: {issue['message']}")
    return "\n".join(lines) + "\n"


def has_gaps(report: dict[str, object]) -> bool:
    """Whether `--check` should fail for missing coverage or invalid metadata."""
    return bool(report["summary"]["missing"] or report["issues"])
