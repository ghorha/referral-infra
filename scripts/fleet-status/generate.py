#!/usr/bin/env python3
"""Fleet status dashboard for ghorha/referral-* repos.

Reports:
  1. Non-main branches with commits not in main (unmerged work)
  2. Non-main branches behind main (stale / need rebase)
  3. main HEAD vs production (OKE image tag, or Vercel/deploy workflow)

Modes:
  --local-root DIR   Scan local clones (default: ../../.. /services when present)
  --github           Use GitHub API (requires GH_PAT or GH_TOKEN with repo scope)
  --kubeconfig PATH  Read live OKE image tags (referral namespace)
  --oci-profile NAME Refresh kubeconfig via OCI CLI before reading cluster
  --oci-cluster OCID Cluster OCID (required with --oci-profile)
  --oci-region NAME  Default us-phoenix-1

Outputs (under --out-dir):
  fleet-status.json / fleet-status.md / fleet-status.html
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Optional
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

ORG = "ghorha"
DEFAULT_BRANCH = "main"
OKE_NAMESPACE = "referral"
OKE_SERVICES = [
    "referral-api-gateway",
    "referral-auth-service",
    "referral-listing-service",
    "referral-claim-service",
    "referral-payment-service",
    "referral-user-service",
    "referral-admin-service",
    "referral-notification-service",
    "referral-support-service",
    "referral-analytics-service",
    "referral-audit-service",
    "referral-orchestration-service",
]
FRONTEND = "referral-frontend"
# Docs / agents / tests are tracked for branch drift only (no OKE deploy).
ALL_REPOS_FALLBACK = OKE_SERVICES + [
    FRONTEND,
    "referral-infra",
    "referral-product",
    "referral-agents",
    "referral-tests",
]


@dataclass
class BranchDrift:
    name: str
    ahead_of_main: int
    behind_main: int
    url: str = ""


@dataclass
class RepoStatus:
    repo: str
    main_sha: str = ""
    default_branch: str = DEFAULT_BRANCH
    branches_ahead: list[BranchDrift] = field(default_factory=list)
    branches_behind: list[BranchDrift] = field(default_factory=list)
    deployed_sha: str = ""
    deploy_source: str = ""  # oke | vercel-workflow | unknown
    undeployed: bool = False
    undeployed_commits: int = 0
    notes: list[str] = field(default_factory=list)
    html_url: str = ""


def run(cmd: list[str], check: bool = True, env: Optional[dict] = None) -> str:
    merged = os.environ.copy()
    if env:
        merged.update(env)
    proc = subprocess.run(cmd, capture_output=True, text=True, env=merged)
    if check and proc.returncode != 0:
        raise RuntimeError(
            f"cmd failed ({proc.returncode}): {' '.join(cmd)}\n{proc.stderr.strip()}"
        )
    return proc.stdout.strip()


def gh_token() -> str:
    return (
        os.environ.get("GH_PAT")
        or os.environ.get("GH_TOKEN")
        or os.environ.get("GITHUB_TOKEN")
        or ""
    )


def github_api(path: str, token: str) -> Any:
    url = f"https://api.github.com{path}"
    req = Request(
        url,
        headers={
            "Accept": "application/vnd.github+json",
            "Authorization": f"Bearer {token}",
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": "vouch-fleet-status",
        },
    )
    with urlopen(req, timeout=60) as resp:
        return json.loads(resp.read().decode())


def github_api_paginated(path: str, token: str) -> list[Any]:
    items: list[Any] = []
    page = 1
    while True:
        sep = "&" if "?" in path else "?"
        chunk = github_api(f"{path}{sep}per_page=100&page={page}", token)
        if not chunk:
            break
        if isinstance(chunk, dict):
            # non-list endpoint
            return [chunk]
        items.extend(chunk)
        if len(chunk) < 100:
            break
        page += 1
    return items


def short(sha: str, n: int = 7) -> str:
    return sha[:n] if sha else "—"


def discover_local_repos(root: Path) -> list[Path]:
    return sorted(
        p for p in root.glob("referral-*") if (p / ".git").exists() and p.is_dir()
    )


def local_repo_status(path: Path) -> RepoStatus:
    name = path.name
    st = RepoStatus(repo=name, html_url=f"https://github.com/{ORG}/{name}")
    try:
        st.main_sha = run(["git", "-C", str(path), "rev-parse", "origin/main"])
    except RuntimeError:
        try:
            st.main_sha = run(["git", "-C", str(path), "rev-parse", "main"])
            st.notes.append("origin/main missing; used local main")
        except RuntimeError:
            st.notes.append("no main branch")
            return st

    try:
        refs = run(
            [
                "git",
                "-C",
                str(path),
                "for-each-ref",
                "--format=%(refname:short)",
                "refs/remotes/origin",
            ]
        ).splitlines()
    except RuntimeError:
        refs = []

    for ref in refs:
        if ref in ("origin", "origin/HEAD") or ref.endswith("/main"):
            continue
        branch = ref[len("origin/") :] if ref.startswith("origin/") else ref
        try:
            ahead = int(
                run(
                    [
                        "git",
                        "-C",
                        str(path),
                        "rev-list",
                        "--count",
                        f"origin/main..{ref}",
                    ]
                )
            )
            behind = int(
                run(
                    [
                        "git",
                        "-C",
                        str(path),
                        "rev-list",
                        "--count",
                        f"{ref}..origin/main",
                    ]
                )
            )
        except RuntimeError:
            continue
        drift = BranchDrift(
            name=branch,
            ahead_of_main=ahead,
            behind_main=behind,
            url=f"https://github.com/{ORG}/{name}/tree/{branch}",
        )
        if ahead > 0:
            st.branches_ahead.append(drift)
        if behind > 0 and ahead >= 0:
            # include behind-only and diverged
            if behind > 0:
                st.branches_behind.append(drift)
    return st


def github_list_repos(token: str) -> list[str]:
    repos = github_api_paginated(f"/orgs/{ORG}/repos?type=all", token)
    names = sorted(
        r["name"] for r in repos if r.get("name", "").startswith("referral-")
    )
    return names or ALL_REPOS_FALLBACK


def github_repo_status(repo: str, token: str) -> RepoStatus:
    st = RepoStatus(repo=repo, html_url=f"https://github.com/{ORG}/{repo}")
    try:
        meta = github_api(f"/repos/{ORG}/{repo}", token)
        st.default_branch = meta.get("default_branch") or DEFAULT_BRANCH
        st.html_url = meta.get("html_url") or st.html_url
        ref = github_api(f"/repos/{ORG}/{repo}/git/ref/heads/{st.default_branch}", token)
        st.main_sha = ref["object"]["sha"]
    except (HTTPError, URLError, KeyError, RuntimeError) as e:
        st.notes.append(f"main lookup failed: {e}")
        return st

    try:
        branches = github_api_paginated(f"/repos/{ORG}/{repo}/branches", token)
    except (HTTPError, URLError) as e:
        st.notes.append(f"branch list failed: {e}")
        return st

    for b in branches:
        name = b.get("name") or ""
        if name == st.default_branch:
            continue
        try:
            cmp_ = github_api(
                f"/repos/{ORG}/{repo}/compare/{st.default_branch}...{name}", token
            )
            ahead = int(cmp_.get("ahead_by") or 0)
            behind = int(cmp_.get("behind_by") or 0)
        except (HTTPError, URLError):
            continue
        drift = BranchDrift(
            name=name,
            ahead_of_main=ahead,
            behind_main=behind,
            url=f"https://github.com/{ORG}/{repo}/tree/{name}",
        )
        if ahead > 0:
            st.branches_ahead.append(drift)
        if behind > 0:
            st.branches_behind.append(drift)
    return st


def refresh_oke_kubeconfig(profile: str, cluster: str, region: str) -> str:
    path = tempfile.mktemp(prefix="kubeconfig-referral-", suffix=".yaml")
    run(
        [
            "oci",
            "--profile",
            profile,
            "ce",
            "cluster",
            "create-kubeconfig",
            "--cluster-id",
            cluster,
            "--region",
            region,
            "--file",
            path,
            "--token-version",
            "2.0.0",
            "--kube-endpoint",
            "PUBLIC_ENDPOINT",
        ],
        env={"OCI_CLI_PROFILE": profile},
    )
    return path


def oke_deployed_tags(kubeconfig: str, oci_profile: str = "") -> dict[str, str]:
    env = {"KUBECONFIG": kubeconfig}
    if oci_profile:
        env["OCI_CLI_PROFILE"] = oci_profile
    raw = run(
        ["kubectl", "get", "deploy", "-n", OKE_NAMESPACE, "-o", "json"],
        env=env,
    )
    data = json.loads(raw)
    out: dict[str, str] = {}
    for item in data.get("items", []):
        name = item["metadata"]["name"]
        containers = item["spec"]["template"]["spec"]["containers"]
        image = containers[0].get("image", "") if containers else ""
        tag = image.rsplit(":", 1)[-1] if ":" in image else image
        if re.fullmatch(r"[0-9a-f]{7,40}", tag):
            out[name] = tag
    return out


def frontend_deployed_sha(token: str) -> tuple[str, str]:
    """Best-effort: last successful deploy workflow run head SHA."""
    try:
        runs = github_api(
            f"/repos/{ORG}/{FRONTEND}/actions/workflows/deploy.yml/runs?status=success&per_page=1",
            token,
        )
        items = runs.get("workflow_runs") or []
        if not items:
            return "", "no successful deploy.yml run"
        return items[0].get("head_sha") or "", "vercel-workflow"
    except (HTTPError, URLError, KeyError) as e:
        return "", f"frontend deploy lookup failed: {e}"


def apply_deploy_drift(
    statuses: list[RepoStatus],
    deployed: dict[str, str],
    token: str,
) -> None:
    by_name = {s.repo: s for s in statuses}
    for svc in OKE_SERVICES:
        st = by_name.get(svc)
        if not st:
            continue
        tag = deployed.get(svc, "")
        st.deployed_sha = tag
        st.deploy_source = "oke" if tag else "unknown"
        if not st.main_sha:
            continue
        if not tag:
            st.notes.append("not found in OKE namespace referral")
            st.undeployed = True
            continue
        if not st.main_sha.startswith(tag) and not tag.startswith(st.main_sha[:7]):
            st.undeployed = True
            # count commits on main not in deployed tag (best-effort via GitHub)
            if token:
                try:
                    cmp_ = github_api(
                        f"/repos/{ORG}/{svc}/compare/{tag}...{st.main_sha}", token
                    )
                    st.undeployed_commits = int(cmp_.get("ahead_by") or 0)
                except (HTTPError, URLError):
                    st.undeployed_commits = -1
            else:
                st.undeployed_commits = -1

    # Frontend
    st = by_name.get(FRONTEND)
    if st and st.main_sha:
        if token:
            sha, src = frontend_deployed_sha(token)
            st.deployed_sha = sha
            st.deploy_source = src if sha else "unknown"
            if sha and sha != st.main_sha:
                st.undeployed = True
                try:
                    cmp_ = github_api(
                        f"/repos/{ORG}/{FRONTEND}/compare/{sha}...{st.main_sha}", token
                    )
                    st.undeployed_commits = int(cmp_.get("ahead_by") or 0)
                except (HTTPError, URLError):
                    st.undeployed_commits = -1
            elif not sha:
                st.notes.append(src or "frontend deploy SHA unknown")
        else:
            st.notes.append("frontend deploy check needs GH_PAT")
            st.deploy_source = "unknown"


def render_md(report: dict[str, Any]) -> str:
    lines = [
        f"# Vouch fleet status",
        "",
        f"Generated **{report['generated_at']}** (UTC).",
        "",
        f"Source: `{report['source']}` · Production: `{report['deploy_source']}`",
        "",
        "## Summary",
        "",
        f"- Repos scanned: **{report['summary']['repos']}**",
        f"- Repos with unmerged branch commits: **{report['summary']['repos_with_unmerged']}**",
        f"- Repos with branches behind main: **{report['summary']['repos_with_behind']}**",
        f"- Repos with undeployed main commits: **{report['summary']['repos_undeployed']}**",
        "",
        "## Main vs production",
        "",
        "| Repo | main | deployed | source | status | undeployed commits |",
        "|------|------|----------|--------|--------|--------------------|",
    ]
    for s in report["repos"]:
        if s["repo"] not in OKE_SERVICES and s["repo"] != FRONTEND:
            continue
        status = "UNDEPLOYED" if s["undeployed"] else ("OK" if s["deployed_sha"] else "UNKNOWN")
        uc = s["undeployed_commits"]
        uc_s = "—" if uc < 0 else str(uc)
        lines.append(
            f"| [{s['repo']}]({s['html_url']}) | `{short(s['main_sha'])}` | `{short(s['deployed_sha'])}` | {s['deploy_source'] or '—'} | **{status}** | {uc_s} |"
        )

    lines += ["", "## Unmerged commits on other branches", ""]
    any_ahead = False
    for s in report["repos"]:
        if not s["branches_ahead"]:
            continue
        any_ahead = True
        lines.append(f"### {s['repo']}")
        lines.append("")
        for b in s["branches_ahead"]:
            lines.append(
                f"- [`{b['name']}`]({b['url']}) — **{b['ahead_of_main']}** commit(s) not in main"
                + (f", behind main by {b['behind_main']}" if b["behind_main"] else "")
            )
        lines.append("")
    if not any_ahead:
        lines.append("_None._")
        lines.append("")

    lines += ["## Branches behind main (stale / need rebase)", ""]
    any_behind = False
    for s in report["repos"]:
        behind_only = [b for b in s["branches_behind"] if b["behind_main"] > 0]
        if not behind_only:
            continue
        any_behind = True
        lines.append(f"### {s['repo']}")
        lines.append("")
        for b in behind_only:
            lines.append(
                f"- [`{b['name']}`]({b['url']}) — **{b['behind_main']}** behind main"
                + (f", ahead by {b['ahead_of_main']}" if b["ahead_of_main"] else "")
            )
        lines.append("")
    if not any_behind:
        lines.append("_None._")
        lines.append("")

    return "\n".join(lines) + "\n"


def render_html(report: dict[str, Any]) -> str:
    def esc(s: str) -> str:
        return (
            s.replace("&", "&amp;")
            .replace("<", "&lt;")
            .replace(">", "&gt;")
            .replace('"', "&quot;")
        )

    rows_prod = []
    for s in report["repos"]:
        if s["repo"] not in OKE_SERVICES and s["repo"] != FRONTEND:
            continue
        if s["undeployed"]:
            badge = '<span class="bad">UNDEPLOYED</span>'
        elif s["deployed_sha"]:
            badge = '<span class="ok">OK</span>'
        else:
            badge = '<span class="unk">UNKNOWN</span>'
        uc = s["undeployed_commits"]
        uc_s = "—" if uc < 0 else str(uc)
        rows_prod.append(
            "<tr>"
            f'<td><a href="{esc(s["html_url"])}">{esc(s["repo"])}</a></td>'
            f"<td><code>{esc(short(s['main_sha']))}</code></td>"
            f"<td><code>{esc(short(s['deployed_sha']))}</code></td>"
            f"<td>{esc(s['deploy_source'] or '—')}</td>"
            f"<td>{badge}</td>"
            f"<td>{esc(uc_s)}</td>"
            "</tr>"
        )

    ahead_blocks = []
    for s in report["repos"]:
        if not s["branches_ahead"]:
            continue
        items = "".join(
            f'<li><a href="{esc(b["url"])}"><code>{esc(b["name"])}</code></a> '
            f"— <strong>{b['ahead_of_main']}</strong> not in main"
            + (
                f", behind {b['behind_main']}"
                if b["behind_main"]
                else ""
            )
            + "</li>"
            for b in s["branches_ahead"]
        )
        ahead_blocks.append(f"<h3>{esc(s['repo'])}</h3><ul>{items}</ul>")

    behind_blocks = []
    for s in report["repos"]:
        behind = [b for b in s["branches_behind"] if b["behind_main"] > 0]
        if not behind:
            continue
        items = "".join(
            f'<li><a href="{esc(b["url"])}"><code>{esc(b["name"])}</code></a> '
            f"— <strong>{b['behind_main']}</strong> behind main"
            + (f", ahead {b['ahead_of_main']}" if b["ahead_of_main"] else "")
            + "</li>"
            for b in behind
        )
        behind_blocks.append(f"<h3>{esc(s['repo'])}</h3><ul>{items}</ul>")

    sm = report["summary"]
    return f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1"/>
<title>Vouch fleet status</title>
<style>
  :root {{
    --bg: #f7f6f2;
    --ink: #1a1a1a;
    --muted: #5c5c5c;
    --line: #d9d6cf;
    --ok: #1f6b3a;
    --bad: #9b1c1c;
    --unk: #6b5a1f;
    --card: #fffef9;
  }}
  * {{ box-sizing: border-box; }}
  body {{
    margin: 0; font-family: "IBM Plex Sans", "Segoe UI", sans-serif;
    background: var(--bg); color: var(--ink); line-height: 1.45;
  }}
  header {{
    padding: 2rem 1.5rem 1rem; border-bottom: 1px solid var(--line);
    background: var(--card);
  }}
  h1 {{ margin: 0 0 .35rem; font-size: 1.75rem; letter-spacing: -0.02em; }}
  .meta {{ color: var(--muted); font-size: .95rem; }}
  main {{ padding: 1.25rem 1.5rem 3rem; max-width: 1100px; margin: 0 auto; }}
  .cards {{ display: grid; grid-template-columns: repeat(auto-fit,minmax(160px,1fr)); gap: .75rem; margin: 1rem 0 1.5rem; }}
  .card {{ background: var(--card); border: 1px solid var(--line); padding: .9rem 1rem; }}
  .card .n {{ font-size: 1.6rem; font-weight: 650; }}
  .card .l {{ color: var(--muted); font-size: .85rem; }}
  h2 {{ margin-top: 2rem; font-size: 1.2rem; }}
  table {{ width: 100%; border-collapse: collapse; background: var(--card); border: 1px solid var(--line); }}
  th, td {{ text-align: left; padding: .55rem .65rem; border-bottom: 1px solid var(--line); font-size: .92rem; vertical-align: top; }}
  th {{ font-weight: 600; background: #f0eee7; }}
  code {{ font-family: "IBM Plex Mono", ui-monospace, monospace; font-size: .85em; }}
  .ok {{ color: var(--ok); font-weight: 650; }}
  .bad {{ color: var(--bad); font-weight: 650; }}
  .unk {{ color: var(--unk); font-weight: 650; }}
  ul {{ padding-left: 1.2rem; }}
  a {{ color: inherit; }}
  footer {{ color: var(--muted); font-size: .85rem; margin-top: 2rem; }}
</style>
</head>
<body>
<header>
  <h1>Vouch fleet status</h1>
  <div class="meta">Generated {esc(report['generated_at'])} UTC · source {esc(report['source'])} · production {esc(report['deploy_source'])}</div>
</header>
<main>
  <div class="cards">
    <div class="card"><div class="n">{sm['repos']}</div><div class="l">Repos scanned</div></div>
    <div class="card"><div class="n">{sm['repos_with_unmerged']}</div><div class="l">With unmerged branch commits</div></div>
    <div class="card"><div class="n">{sm['repos_with_behind']}</div><div class="l">With branches behind main</div></div>
    <div class="card"><div class="n">{sm['repos_undeployed']}</div><div class="l">Main not in production</div></div>
  </div>

  <h2>Main vs production</h2>
  <table>
    <thead><tr><th>Repo</th><th>main</th><th>deployed</th><th>source</th><th>status</th><th>undeployed commits</th></tr></thead>
    <tbody>
      {''.join(rows_prod)}
    </tbody>
  </table>

  <h2>Unmerged commits on other branches</h2>
  {''.join(ahead_blocks) if ahead_blocks else '<p><em>None.</em></p>'}

  <h2>Branches behind main</h2>
  {''.join(behind_blocks) if behind_blocks else '<p><em>None.</em></p>'}

  <footer>ghorha/referral-infra · scripts/fleet-status</footer>
</main>
</body>
</html>
"""


def build_report(
    statuses: list[RepoStatus],
    source: str,
    deploy_source: str,
) -> dict[str, Any]:
    repos = [asdict(s) for s in statuses]
    summary = {
        "repos": len(statuses),
        "repos_with_unmerged": sum(1 for s in statuses if s.branches_ahead),
        "repos_with_behind": sum(1 for s in statuses if s.branches_behind),
        "repos_undeployed": sum(1 for s in statuses if s.undeployed),
    }
    return {
        "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "source": source,
        "deploy_source": deploy_source,
        "summary": summary,
        "repos": repos,
    }


def default_local_root() -> Optional[Path]:
    here = Path(__file__).resolve()
    # referral-infra/scripts/fleet-status/generate.py → services/
    candidate = here.parents[3]
    if candidate.name == "services" or any(candidate.glob("referral-*/.git")):
        return candidate if candidate.name == "services" else candidate / "services"
    # workspace/services
    ws = Path("/Users/abhaysingh/Documents/development/referral/services")
    if ws.exists():
        return ws
    return None


def main() -> int:
    ap = argparse.ArgumentParser(description="Generate Vouch fleet status dashboard")
    ap.add_argument("--local-root", type=Path, help="Directory of referral-* git clones")
    ap.add_argument("--github", action="store_true", help="Use GitHub API")
    ap.add_argument("--kubeconfig", type=Path, help="Existing kubeconfig for OKE")
    ap.add_argument("--oci-profile", default="", help="OCI CLI profile to refresh kubeconfig")
    ap.add_argument("--oci-cluster", default=os.environ.get("OKE_CLUSTER_OCID", ""))
    ap.add_argument("--oci-region", default=os.environ.get("OCI_CLI_REGION", "us-phoenix-1"))
    ap.add_argument(
        "--out-dir",
        type=Path,
        default=Path(__file__).resolve().parents[2] / "docs" / "fleet-status",
    )
    args = ap.parse_args()

    token = gh_token()
    statuses: list[RepoStatus] = []
    source = ""

    if args.github:
        if not token:
            print("error: --github requires GH_PAT / GH_TOKEN", file=sys.stderr)
            return 2
        source = "github-api"
        for name in github_list_repos(token):
            print(f"scan {name} (github)", file=sys.stderr)
            statuses.append(github_repo_status(name, token))
    else:
        root = args.local_root or default_local_root()
        if not root or not root.exists():
            print(
                "error: no --local-root and no services/ clones found; use --github",
                file=sys.stderr,
            )
            return 2
        source = f"local:{root}"
        for path in discover_local_repos(root):
            print(f"scan {path.name} (local)", file=sys.stderr)
            statuses.append(local_repo_status(path))

    kubeconfig = str(args.kubeconfig) if args.kubeconfig else ""
    oci_profile = args.oci_profile
    deploy_source = "none"
    deployed: dict[str, str] = {}

    if oci_profile:
        if not args.oci_cluster:
            print("error: --oci-profile requires --oci-cluster / OKE_CLUSTER_OCID", file=sys.stderr)
            return 2
        print("refreshing OKE kubeconfig", file=sys.stderr)
        kubeconfig = refresh_oke_kubeconfig(oci_profile, args.oci_cluster, args.oci_region)

    if kubeconfig:
        print("reading OKE deployments", file=sys.stderr)
        deployed = oke_deployed_tags(kubeconfig, oci_profile=oci_profile or "GHORHA")
        deploy_source = "oke"
    elif token and args.github:
        deploy_source = "github-workflows-partial"

    apply_deploy_drift(statuses, deployed, token if token else "")

    report = build_report(statuses, source=source, deploy_source=deploy_source)
    out = args.out_dir
    out.mkdir(parents=True, exist_ok=True)
    (out / "fleet-status.json").write_text(json.dumps(report, indent=2) + "\n")
    (out / "fleet-status.md").write_text(render_md(report))
    (out / "fleet-status.html").write_text(render_html(report))
    # Pages-friendly index
    (out / "index.html").write_text(render_html(report))

    print(
        f"wrote {out}/fleet-status.{{json,md,html}} "
        f"(undeployed={report['summary']['repos_undeployed']}, "
        f"unmerged={report['summary']['repos_with_unmerged']})",
        file=sys.stderr,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
