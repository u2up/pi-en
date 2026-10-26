#!/usr/bin/env python3
"""Safe, project-owned behavior specification runner."""
import argparse, json, os, re, shutil, subprocess, sys, tempfile
from pathlib import Path

try:
    import yaml
except ImportError as exc:
    sys.exit("pien behavior: PyYAML is required; use the pi-en Nix runtime or install PyYAML")

VERSION = "v1"
ARGUMENT_TYPES = {"string", "integer", "boolean"}
COMPLIANCE_MODES = {"advisory", "enforced"}
PHASES = {"given", "when", "then"}
ID_RE = re.compile(r"^[A-Z0-9]+-BHV-[0-9]{8}-[0-9]{6}-[0-9]{3}$")
SLUG_RE = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")


def fail(message):
    raise ValueError(message)

def load(path):
    try:
        with open(path, encoding="utf-8") as stream:
            value = yaml.safe_load(stream)
    except yaml.YAMLError as exc:
        fail(f"invalid YAML in {path}: {exc}")
    if not isinstance(value, dict): fail(f"{path} must contain a YAML mapping")
    return value

def dump(path, value):
    with open(path, "x", encoding="utf-8") as stream:
        yaml.safe_dump(value, stream, sort_keys=False)

def group_valid(group):
    return isinstance(group, str) and bool(group) and all(SLUG_RE.fullmatch(x) for x in group.split("/"))

def group_declared(group, groups):
    return any(group == declared or group.startswith(declared + "/") for declared in groups)

def root(args):
    candidate = Path(args.project_root).resolve() / "pi-en-behaviors"
    # Snapshot output is a project-local artifact.  Do not resolve a behavior
    # root link and then write through it outside the selected project.
    if candidate.is_symlink():
        fail("behavior root must not be a symlink")
    if not candidate.is_dir(): fail(f"behavior root not found: {candidate}; run 'pien behavior init'")
    return candidate

def manifest(base):
    data = load(base / "MANIFEST.yaml")
    if data.get("schema") != VERSION: fail("unsupported manifest schema; migrate the behavior root to v1")
    for key in ("repository_id", "item_key", "glossary", "adapter"):
        if not isinstance(data.get(key), str) or not data[key]: fail(f"manifest requires {key}")
    if data.get("compliance") not in COMPLIANCE_MODES:
        fail("manifest compliance must be advisory or enforced")
    return data

def glossary(base, man):
    data = load(base / man["glossary"])
    if data.get("language_version") != VERSION: fail("unsupported glossary language version; migrate the glossary to v1")
    terms = data.get("terms")
    if not isinstance(terms, dict): fail("glossary requires a terms mapping")
    groups = data.get("groups", [])
    if not isinstance(groups, list) or not all(group_valid(x) for x in groups): fail("glossary groups must be normalized slash-separated slugs")
    for name, term in terms.items():
        if not isinstance(name, str) or not isinstance(term, dict): fail("glossary terms must be named mappings")
        if term.get("phase") not in PHASES:
            fail(f"glossary term {name} phase must be given, when, or then")
        arguments = term.get("args", {})
        if not isinstance(arguments, dict): fail(f"glossary term {name} args must be a mapping")
        for argument, kind in arguments.items():
            if not isinstance(argument, str) or not isinstance(kind, str) or kind not in ARGUMENT_TYPES:
                fail(f"glossary term {name} has unsupported argument type for {argument}")
    return data

def specs(base):
    directory = base / "specifications"
    if not directory.is_dir(): fail("behavior root has no specifications directory")
    files = sorted(directory.iterdir())
    result = []
    for path in files:
        if path.is_symlink() or not path.is_file():
            fail(f"specification must be a regular file: {path.name}")
        if path.suffix not in (".yaml", ".yml"): continue
        if path.suffix != ".yaml" or not ID_RE.fullmatch(path.stem): fail(f"unexpected YAML specification: {path.name}")
        item = load(path); item["_path"] = path; result.append(item)
    return result

def validate(base, require_scenarios=True):
    man = manifest(base); lex = glossary(base, man); entries = specs(base); seen = set()
    terms = lex["terms"]
    for item in entries:
        ident = item.get("id")
        if not isinstance(ident, str) or not ID_RE.fullmatch(ident): fail(f"{item['_path']}: invalid local BHV id")
        if ident in seen: fail(f"duplicate BHV id: {ident}")
        seen.add(ident)
        if item["_path"].stem != ident: fail(f"{item['_path']}: filename must match id")
        if item.get("schema") != VERSION or item.get("language_version") != lex["language_version"]: fail(f"{ident}: unsupported schema or language version")
        if item.get("status") not in ("active", "deprecated", "superseded"): fail(f"{ident}: invalid status")
        if not group_valid(item.get("group")): fail(f"{ident}: invalid group")
        if not group_declared(item["group"], lex["groups"]): fail(f"{ident}: group is not declared by the glossary")
        for key in ("title", "feature", "rule"):
            if not isinstance(item.get(key), str) or not item[key]: fail(f"{ident}: requires {key}")
        scenarios = item.get("scenarios")
        if not isinstance(scenarios, list) or (require_scenarios and not scenarios): fail(f"{ident}: requires scenarios")
        scenario_ids = set()
        for scenario in scenarios:
            if not isinstance(scenario, dict) or not isinstance(scenario.get("id"), str): fail(f"{ident}: scenario requires id")
            if scenario["id"] in scenario_ids: fail(f"{ident}: duplicate scenario id {scenario['id']}")
            scenario_ids.add(scenario["id"])
            for phase in ("given", "when", "then"):
                steps = scenario.get(phase, [])
                if not isinstance(steps, list): fail(f"{ident}/{scenario['id']}: {phase} must be a list")
                for step in steps:
                    if not isinstance(step, dict) or not isinstance(step.get("term"), str): fail(f"{ident}/{scenario['id']}: invalid {phase} step")
                    term = terms.get(step["term"])
                    if not isinstance(term, dict) or term.get("deprecated") is True: fail(f"{ident}/{scenario['id']}: unknown or deprecated term {step['term']}")
                    if term.get("phase") != phase: fail(f"{ident}/{scenario['id']}: term {step['term']} is not a {phase} term")
                    args = step.get("args", {})
                    if not isinstance(args, dict): fail(f"{ident}/{scenario['id']}: term args must be a mapping")
                    required = term.get("args", {})
                    if not isinstance(required, dict) or set(args) != set(required): fail(f"{ident}/{scenario['id']}: argument shape does not match {step['term']}")
                    for name, kind in required.items():
                        val = args[name]
                        if kind == "string" and not isinstance(val, str): fail(f"{ident}: {name} must be string")
                        if kind == "integer" and (not isinstance(val, int) or isinstance(val, bool)): fail(f"{ident}: {name} must be integer")
                        if kind == "boolean" and not isinstance(val, bool): fail(f"{ident}: {name} must be boolean")
    return man, lex, entries

def init(args):
    base = Path(args.project_root).resolve() / "pi-en-behaviors"; base.mkdir(parents=True, exist_ok=True); (base / "specifications").mkdir(exist_ok=True)
    man = base / "MANIFEST.yaml"; lex = base / "GLOSSARY.yaml"; adapter = base / "adapter"
    if not man.exists(): dump(man, {"schema": VERSION, "repository_id": "replace-me", "item_key": "LOCAL", "glossary": "GLOSSARY.yaml", "adapter": "./adapter", "compliance": "advisory"})
    if not lex.exists(): dump(lex, {"language_version": VERSION, "groups": ["features"], "terms": {}})
    if not adapter.exists():
        adapter.write_text("#!/usr/bin/env bash\nset -euo pipefail\n# describe prints a JSON term map; phases receive TERM JSON_FILE STATE_DIR.\nif [ \"${1:-}\" = describe ]; then printf '{\\\"terms\\\":{}}\\n'; exit 0; fi\nexit 0\n", encoding="utf-8"); adapter.chmod(0o755)
    print(f"initialized {base}")

def selected(entries, group):
    return [x for x in entries if not group or x["group"] == group or x["group"].startswith(group + "/")]

def python_cache_prefix():
    cache_home = os.environ.get("XDG_CACHE_HOME") or str(Path.home() / ".cache")
    return str(Path(cache_home) / "pi-en" / "python-bytecode")

def adapter_env(work):
    """Return the deterministic, coordination-free adapter environment."""
    # The packaged interpreter supplies its fixed Nix runtime.  Never inherit
    # PATH: an adapter may need its pinned Python, but not caller-controlled
    # commands.  The fallback keeps direct interpreter use deterministic.
    runtime_path = os.environ.get("PI_EN_BEHAVIOR_RUNTIME_PATH", os.defpath)
    return {
        "PATH": runtime_path, "TZ": "UTC", "LC_ALL": "C", "LANG": "C",
        "HOME": str(work / "home"), "TMPDIR": str(work / "tmp"),
        "PYTHONPYCACHEPREFIX": os.environ.get("PYTHONPYCACHEPREFIX") or python_cache_prefix(),
    }

def lint(args):
    base = root(args); man, lex, entries = validate(base)
    adapter = (base / man["adapter"]).resolve()
    if not adapter.is_file() or not os.access(adapter, os.X_OK): fail("manifest adapter must be executable")
    try:
        with tempfile.TemporaryDirectory(prefix="pien-behavior-lint-") as temporary:
            work = Path(temporary)
            (work / "home").mkdir(); (work / "tmp").mkdir()
            described = json.loads(subprocess.check_output(
                [str(adapter), "describe"], text=True, env=adapter_env(work), cwd=work))
    except (subprocess.CalledProcessError, json.JSONDecodeError) as exc: fail(f"adapter describe failed: {exc}")
    supported = described.get("terms", described) if isinstance(described, dict) else None
    if not isinstance(supported, dict) or set(supported) != set(lex["terms"]): fail("adapter describe terms must exactly match glossary terms")
    print(f"lint passed: {len(entries)} behavior specifications")

def test(args):
    base = root(args); man, _, entries = validate(base); entries = selected(entries, args.group)
    adapter = (base / man["adapter"]).resolve(); failures = 0
    for item in entries:
        if item["status"] != "active": continue
        for scenario in item["scenarios"]:
            state = Path(tempfile.mkdtemp(prefix="pien-behavior-"))
            try:
                # Do not pass caller-controlled PATH or coordination settings to adapters.
                env = adapter_env(state)
                (state / "home").mkdir(); (state / "tmp").mkdir()
                for phase in ("given", "when", "then"):
                    for step in scenario.get(phase, []):
                        data = state / "input.json"; data.write_text(json.dumps(step.get("args", {})), encoding="utf-8")
                        call = subprocess.run([str(adapter), phase, step["term"], str(data), str(state)], env=env, cwd=state, text=True, capture_output=True)
                        if call.returncode:
                            raise RuntimeError((call.stderr or call.stdout).strip() or "adapter failed")
                print(f"PASS {item['id']} {scenario['id']}")
            except Exception as exc:
                failures += 1; print(f"FAIL {item['id']} {scenario['id']}: {exc}", file=sys.stderr)
            finally: shutil.rmtree(state, ignore_errors=True)
    if failures: sys.exit(1)

def list_specs(args):
    _, _, entries = validate(root(args))
    for item in selected(entries, args.group): print(f"{item['id']}\t{item['group']}\t{item['title']}")

def index(args):
    _, _, entries = validate(root(args)); out = [{k: x.get(k, [] if k in ('tags','satisfies') else None) for k in ('id','group','title','feature','rule','status','tags','satisfies')} | {"scenario_count": len(x['scenarios'])} for x in entries]
    print(json.dumps(out, indent=2, sort_keys=True))

def document(args):
    """Render a reviewable, adapter-independent view of the local BHVs."""
    man, _, entries = validate(root(args))
    print(f"# Behavior documentation: {man['repository_id']}")
    print("\nGenerated from local BHV metadata. This catalog intentionally omits adapter details.")
    print("\n## Catalog")
    groups = sorted({item['group'] for item in entries})
    for group in groups:
        print(f"- [{group}](#{group.replace('/', '-')})")
    for group in groups:
        # Keep catalog targets stable for slash-separated logical groups;
        # Markdown heading sluggers differ on how they treat slashes.
        print(f'\n<a id="{group.replace("/", "-")}"></a>\n## {group}')
        for item in (entry for entry in entries if entry['group'] == group):
            print(f"\n### {item['title']} (`{item['id']}`)")
            print(f"- Status: {item['status']}")
            print(f"- Feature: {item['feature']}")
            print(f"- Rule: {item['rule']}")
            if item.get('tags'):
                print(f"- Tags: {', '.join(item['tags'])}")
            if item.get('satisfies'):
                print(f"- Acceptance references: {', '.join(item['satisfies'])}")
            print(f"- Scenarios ({len(item['scenarios'])}):")
            for scenario in item['scenarios']:
                print(f"  - {scenario['title']} (`{scenario['id']}`)")

def snapshot(args):
    # The coordination source is deliberately explicit: snapshots are an opt-in
    # local traceability artifact, never discovered through the environment.
    if not args.repo_id.strip():
        fail("requirements snapshot requires a non-empty repository ID")
    coord = Path(args.coord_dir).resolve()
    if not coord.is_dir(): fail(f"coordination directory not found: {coord}")
    try:
        revision = subprocess.check_output(
            ["git", "-C", str(coord), "rev-parse", "HEAD"], text=True).strip()
        dirty = subprocess.check_output(
            ["git", "-C", str(coord), "status", "--porcelain", "--untracked-files=all"],
            text=True)
    except (OSError, subprocess.CalledProcessError):
        fail("coordination directory must be a Git checkout")
    if dirty:
        fail("coordination directory must be a clean Git checkout")
    requirements = []
    directory = coord / "requirements"
    if not directory.is_dir(): fail("coordination directory has no requirements directory")
    # Enumerate blobs recorded by the revision above, rather than the working
    # directory.  Ignored/untracked YAML can otherwise be silently included
    # while the snapshot claims it came from HEAD.
    try:
        tracked = subprocess.check_output(
            ["git", "-C", str(coord), "ls-tree", "-r", "-z",
             "--format=%(objectmode) %(objecttype) %(path)", revision,
             "--", "requirements"], text=True).split("\0")
    except (OSError, subprocess.CalledProcessError):
        fail("coordination directory must expose requirements at its HEAD revision")
    paths = []
    for entry in tracked:
        if not entry: continue
        mode, object_type, relative = entry.split(" ", 2)
        path = Path(relative)
        if path.parent == Path("requirements") and path.suffix == ".yaml":
            if mode not in ("100644", "100755") or object_type != "blob":
                fail(f"tracked requirement must be a regular file: {relative}")
            paths.append(relative)
    for relative in sorted(paths):
        try:
            content = subprocess.check_output(
                ["git", "-C", str(coord), "show", f"{revision}:{relative}"], text=True)
            item = yaml.safe_load(content)
        except (OSError, subprocess.CalledProcessError, yaml.YAMLError) as exc:
            fail(f"invalid YAML in tracked requirement {relative}: {exc}")
        if not isinstance(item, dict):
            fail(f"tracked requirement {relative} must contain a YAML mapping")
        applicable = item.get("applicable_repos")
        if applicable is not None and (not isinstance(applicable, list) or not all(isinstance(x, str) and x for x in applicable)):
            fail(f"{relative}: applicable_repos must be a list of repository IDs")
        policy = item.get("behavior_coverage", "optional")
        if policy not in ("required", "optional", "not-applicable"):
            fail(f"{path}: invalid behavior_coverage policy")
        if applicable is None or args.repo_id in applicable:
            requirements.append({
                "requirement_key": item.get("requirement_key"), "item_id": item.get("id"),
                "status": item.get("status"), "title": item.get("title"),
                "body": item.get("body"), "applicable_repos": applicable,
                "behavior_coverage": policy,
            })
    base = root(args)
    output = base / "requirements.snapshot.yaml"
    # Never follow an existing link: the opt-in snapshot command may update
    # only its project-local tracked artifact.
    if output.is_symlink():
        fail("requirements snapshot output must not be a symlink")
    # Replace an existing regular output atomically.  In particular, this
    # replaces a hard link rather than truncating the link's other name.
    temp_name = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=base,
                                         prefix=".requirements.snapshot.", delete=False) as stream:
            temp_name = Path(stream.name)
            yaml.safe_dump({"schema": VERSION, "source_revision": revision,
                            "repository_id": args.repo_id, "requirements": requirements}, stream,
                           sort_keys=False)
        os.replace(temp_name, output)
    finally:
        if temp_name is not None and temp_name.exists():
            temp_name.unlink()
    print(output)

def coverage(args):
    # Coverage must report active BHVs with no scenarios rather than rejecting
    # the specification before it can produce the advisory/enforced report.
    base = root(args); man, _, entries = validate(base, require_scenarios=False)
    snapshot_path = base / "requirements.snapshot.yaml"
    violations = []
    snapshot_data = None
    if not snapshot_path.is_file():
        violations.append("missing requirements snapshot")
    else:
        snapshot_data = load(snapshot_path)
        if snapshot_data.get("schema") != VERSION or snapshot_data.get("repository_id") != man["repository_id"]:
            violations.append("requirements snapshot does not match this repository")
    requirements = snapshot_data.get("requirements", []) if isinstance(snapshot_data, dict) else []
    if not isinstance(requirements, list):
        violations.append("requirements snapshot has invalid requirements")
        requirements = []
    by_reference = {}
    for requirement in requirements:
        if not isinstance(requirement, dict):
            violations.append("requirements snapshot has invalid requirement entry")
            continue
        for key in ("requirement_key", "item_id"):
            if isinstance(requirement.get(key), str): by_reference[requirement[key]] = requirement
    claims = {}
    for item in entries:
        references = item.get("satisfies", [])
        if not isinstance(references, list) or not all(isinstance(x, str) for x in references):
            violations.append(f"{item['id']} has invalid satisfies references")
            continue
        executable = item["status"] == "active" and bool(item.get("scenarios"))
        if item["status"] == "active" and not executable:
            violations.append(f"{item['id']} has no executable scenarios")
        for reference in references:
            requirement = by_reference.get(reference)
            if requirement is None:
                violations.append(f"{item['id']} claims missing snapshot requirement {reference}")
            elif requirement.get("status") != "active":
                violations.append(f"{item['id']} claims inactive requirement {reference}")
            elif executable:
                # Required coverage must be backed by a behavior that can run,
                # not merely by a traceability reference.
                claims.setdefault(requirement.get("item_id"), []).append(item["id"])
    for requirement in requirements:
        if not isinstance(requirement, dict): continue
        if requirement.get("status") == "active" and requirement.get("behavior_coverage") == "required" and not claims.get(requirement.get("item_id")):
            violations.append(f"required requirement {requirement.get('requirement_key')} has no active BHV coverage")
    report = {"repository_id": man["repository_id"], "compliance": man["compliance"],
              "passed": not violations, "violations": violations}
    if args.format == "json": print(json.dumps(report, indent=2, sort_keys=True))
    else:
        print("coverage passed" if not violations else "coverage violations:")
        for violation in violations: print(f"- {violation}")
    if violations and man["compliance"] == "enforced": sys.exit(1)

def new(args):
    base = root(args); man = manifest(base); lex = glossary(base, man)
    if not group_valid(args.group): fail("invalid group")
    if not group_declared(args.group, lex["groups"]): fail("group is not declared by the glossary")
    ident = args.id
    if not ID_RE.fullmatch(ident) or not ident.startswith(man['item_key'] + '-BHV-'): fail("id must be a local ITEMKEY-BHV timestamp id")
    path = base / "specifications" / (ident + ".yaml")
    if path.exists(): fail(f"specification exists: {ident}")
    dump(path, {"schema": VERSION, "language_version": VERSION, "id": ident, "group": args.group, "status": "active", "title": args.title, "feature": args.title, "rule": "Replace with a reviewable rule", "tags": [], "satisfies": [], "scenarios": [{"id":"example", "title":"Replace with a contrasting acceptance example", "given":[], "when":[], "then":[]}]})
    print(path)

def regroup(args):
    base = root(args); _, lex, entries = validate(base)
    if not group_valid(args.group): fail("invalid group")
    if not group_declared(args.group, lex["groups"]): fail("group is not declared by the glossary")
    matches = [x for x in entries if x['id'] == args.id]
    if len(matches) != 1: fail(f"unknown BHV id: {args.id}")
    path = matches[0].pop('_path'); matches[0]['group'] = args.group; matches[0].pop('_path', None)
    with open(path, 'w', encoding='utf-8') as stream: yaml.safe_dump(matches[0], stream, sort_keys=False)
    print(f"regrouped {args.id} to {args.group}")

def main():
    parser = argparse.ArgumentParser(prog="pien behavior"); parser.add_argument("--project-root", default=".")
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("init").set_defaults(func=init)
    for name, func in (("lint",lint),("test",test),("list",list_specs),("index",index),("document",document),("coverage",coverage)):
        p=sub.add_parser(name); p.set_defaults(func=func)
        if name in ("test","list"): p.add_argument("--group")
        if name == "coverage": p.add_argument("--format", choices=("text", "json"), default="text")
    p=sub.add_parser("new"); p.add_argument("--id",required=True); p.add_argument("--group",required=True); p.add_argument("--title",required=True); p.set_defaults(func=new)
    p=sub.add_parser("regroup"); p.add_argument("id"); p.add_argument("--group",required=True); p.set_defaults(func=regroup)
    p=sub.add_parser("requirements"); nested=p.add_subparsers(dest="requirements_command", required=True)
    p=nested.add_parser("snapshot"); p.add_argument("--coord-dir", required=True); p.add_argument("--repo-id", required=True); p.set_defaults(func=snapshot)
    args=parser.parse_args()
    try: args.func(args)
    except ValueError as exc: print(f"pien behavior: {exc}", file=sys.stderr); sys.exit(2)
if __name__ == '__main__': main()
