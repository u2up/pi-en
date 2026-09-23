# Shared helpers for pi-en coordination commands.

coord_die() {
  printf 'pi-en-coord: %s\n' "$*" >&2
  exit 1
}

coord_note() {
  printf 'pi-en-coord: %s\n' "$*" >&2
}

coord_abs() {
  realpath -m "$1"
}

coord_abs_lexical() {
  realpath -sm "$1"
}

coord_project_root() {
  local root abs_root pwd_abs project_root

  if [ -n "${PI_EN_COORD_PROJECT_ROOT:-}" ]; then
    coord_abs "$PI_EN_COORD_PROJECT_ROOT"
    return
  fi

  root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  if [ -n "$root" ]; then
    abs_root="$(coord_abs "$root")"
    case "$abs_root" in
      */.pi-en/coordination|*/.pi-en/coordination/*)
        project_root="${abs_root%%/.pi-en/coordination*}"
        coord_abs "$project_root"
        return
        ;;
    esac
    printf '%s\n' "$abs_root"
    return
  fi

  pwd_abs="$(pwd -P)"
  case "$pwd_abs" in
    */.pi-en/coordination|*/.pi-en/coordination/*)
      project_root="${pwd_abs%%/.pi-en/coordination*}"
      coord_abs "$project_root"
      ;;
    *)
      coord_abs "$pwd_abs"
      ;;
  esac
}

coord_impl_config_filename() {
  printf '%s\n' ".pi-en-coordination.yaml"
}

coord_impl_config_path() {
  local project_root
  project_root="${1:-}"
  if [ -z "$project_root" ]; then
    project_root="$(coord_project_root)"
  fi
  printf '%s/%s\n' "$(coord_abs "$project_root")" "$(coord_impl_config_filename)"
}

coord_impl_config_existing_path() {
  local project_root file
  project_root="${1:-}"
  file="$(coord_impl_config_path "$project_root")"
  if [ -f "$file" ]; then
    printf '%s\n' "$file"
    return 0
  fi
  return 1
}

coord_impl_config_exists() {
  local project_root
  project_root="${1:-}"
  [ -f "$(coord_impl_config_path "$project_root")" ]
}

coord_impl_config_source() {
  local project_root file
  project_root="${1:-}"
  file="$(coord_impl_config_path "$project_root")"
  if [ -f "$file" ]; then
    coord_impl_config_filename
    return 0
  fi
  return 1
}

coord_impl_config_read_value() {
  local file key
  file="$1"
  key="$2"
  awk -v key="$key" '
    /^[[:space:]]*#/ { next }
    index($0, key ":") == 1 {
      sub("^[^:]+:[[:space:]]*", "")
      print
      exit
    }
  ' "$file"
}

coord_impl_config_value() {
  local key project_root file value
  key="$1"
  project_root="${2:-}"
  file="$(coord_impl_config_existing_path "$project_root" || true)"
  value=""
  if [ -n "$file" ]; then
    value="$(coord_impl_config_read_value "$file" "$key")"
  fi
  coord_yaml_unquote "$value"
}

coord_impl_config_set_value() {
  local key value project_root file rendered tmp
  key="$1"
  value="$2"
  project_root="${3:-}"
  file="$(coord_impl_config_path "$project_root")"
  rendered="$(coord_yaml_scalar "$value")"
  mkdir -p "$(dirname "$file")"
  if [ ! -f "$file" ]; then
    {
      printf 'version: 1\n'
      printf '%s: %s\n' "$key" "$rendered"
    } >"$file"
    return
  fi

  tmp="$(mktemp "${TMPDIR:-/tmp}/pi-en-coord-config.XXXXXX")" \
    || coord_die "failed to create temporary file"
  awk -v key="$key" -v rendered="$rendered" '
    BEGIN { written = 0 }
    index($0, key ":") == 1 {
      if (!written) {
        print key ": " rendered
        written = 1
      }
      next
    }
    { print }
    END {
      if (!written) print key ": " rendered
    }
  ' "$file" >"$tmp" || {
    rm -f "$tmp"
    coord_die "failed to update $(coord_impl_config_filename)"
  }
  mv "$tmp" "$file"
}

coord_remote_local_path() {
  local remote
  remote="$1"
  case "$remote" in
    "")
      return 1
      ;;
    file://*)
      printf '%s\n' "${remote#file://}"
      return 0
      ;;
    *://*|*:*)
      return 1
      ;;
    /*|./*|../*|*/*|.*)
      printf '%s\n' "$remote"
      return 0
      ;;
  esac
  return 1
}

coord_normalize_coordination_remote() {
  local remote project_root local_path abs_path
  remote="$1"
  project_root="${2:-}"
  if [ -z "$project_root" ]; then
    project_root="$(coord_project_root)"
  fi

  if local_path="$(coord_remote_local_path "$remote" 2>/dev/null)"; then
    case "$local_path" in
      /*) abs_path="$(coord_abs "$local_path")" ;;
      *) abs_path="$(coord_abs "$project_root/$local_path")" ;;
    esac
    case "$remote" in
      file://*) printf 'file://%s\n' "$abs_path" ;;
      *) printf '%s\n' "$abs_path" ;;
    esac
    return
  fi

  printf '%s\n' "$remote"
}

coord_env_coordination_remote() {
  local remote
  if [ -n "${PI_EN_COORD_REMOTE:-}" ]; then
    remote="$PI_EN_COORD_REMOTE"
  else
    return 1
  fi
  coord_normalize_coordination_remote "$remote"
}

coord_repo_name_from_url() {
  local url name
  url="$1"
  url="${url%%\#*}"
  url="${url%%\?*}"
  url="${url%/}"
  name="${url##*/}"
  name="${name%.git}"
  printf '%s\n' "$name"
}

coord_infer_repo_id_from_remote() {
  local remote name
  remote="$(git remote get-url origin 2>/dev/null || true)"
  [ -n "$remote" ] || return 1
  name="$(coord_repo_name_from_url "$remote")"
  [ -n "$name" ] || return 1
  printf '%s\n' "$name"
}

coord_registry_repo_id_for_remote() {
  local remote coord_dir repos_dir file repo_id hit matches count registered
  remote="$1"
  coord_dir="${2:-}"
  repos_dir="$(coord_registry_path "$coord_dir")"
  [ -d "$repos_dir" ] || return 1
  matches=""
  while IFS= read -r file; do
    [ -n "$file" ] || continue
    repo_id="$(coord_repo_manifest_value "$file" repo_id || true)"
    [ -n "$repo_id" ] || repo_id="$(basename "$(dirname "$file")")"
    hit="no"
    while IFS= read -r registered; do
      [ "$registered" = "$remote" ] && hit="yes"
    done < <(coord_repo_manifest_list_values "$file" remotes)
    [ "$hit" = "yes" ] && matches="${matches}${repo_id}"$'\n'
  done < <(find "$repos_dir" -mindepth 2 -maxdepth 2 -name REPO.md -type f 2>/dev/null | sort)
  count="$(printf '%s' "$matches" | sed '/^$/d' | wc -l | tr -d ' ')"
  [ "$count" != "0" ] || return 1
  [ "$count" = "1" ] || coord_die "git remote origin '$remote' is ambiguous in coordination registry"
  printf '%s' "$matches" | sed '/^$/d'
}

coord_repo_id_is_valid() {
  local repo_id
  repo_id="$1"
  [[ "$repo_id" =~ ^[a-z][a-z0-9._-]*[a-z0-9]$ ]] || return 1
  case "$repo_id" in
    *..*|.*|*-|*/*) return 1 ;;
  esac
  return 0
}

coord_repo_manifest_value() {
  local file key
  file="$1"
  key="$2"
  coord_frontmatter_value "$file" "$key"
}

coord_repo_manifest_list_values() {
  local file key
  file="$1"
  key="$2"
  awk -v key="$key" '
    function unquote(value) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      gsub(/^'"'"'|'"'"'$/, "", value)
      gsub(/^"|"$/, "", value)
      return value
    }
    NR == 1 && $0 == "---" { in_fm=1; next }
    in_fm && $0 == "---" { exit }
    in_fm && $0 ~ "^" key ":[[:space:]]*$" { in_list=1; next }
    in_list && /^[[:space:]]*-[[:space:]]*/ {
      line=$0; sub("^[[:space:]]*-[[:space:]]*", "", line); print unquote(line); next
    }
    in_list && /^[^[:space:]]/ { exit }
  ' "$file"
}

coord_registry_path() {
  local coord_dir
  coord_dir="${1:-}"
  [ -n "$coord_dir" ] || coord_dir="$(coord_default_dir)"
  printf '%s/repos\n' "$(coord_abs "$coord_dir")"
}

coord_legacy_registry_path() {
  local coord_dir
  coord_dir="${1:-}"
  [ -n "$coord_dir" ] || coord_dir="$(coord_default_dir)"
  printf '%s/repositories.yaml\n' "$(coord_abs "$coord_dir")"
}

coord_legacy_registry_matches() {
  local repo_id coord_dir file
  repo_id="$1"
  coord_dir="${2:-}"
  file="$(coord_legacy_registry_path "$coord_dir")"
  [ -f "$file" ] || return 1
  awk -v want="$repo_id" '
    function trim(value) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      gsub(/^'"'"'|'"'"'$/, "", value)
      gsub(/^"|"$/, "", value)
      return value
    }
    function emit_aliases(  i) {
      for (i in aliases) {
        if (i == want) print repo ":alias:" status
      }
      delete aliases
    }
    function finish_record() {
      if (repo == "") return
      if (status == "") status="active"
      if (repo == want) print repo ":canonical:" status
      emit_aliases()
    }
    /^[[:space:]]*-[[:space:]]*repo_id:/ {
      finish_record()
      repo=$0
      sub(/^[[:space:]]*-[[:space:]]*repo_id:[[:space:]]*/, "", repo)
      repo=trim(repo)
      status="active"
      in_aliases=0
      next
    }
    repo != "" && /^[[:space:]]*repo_id:/ {
      repo=$0
      sub(/^[[:space:]]*repo_id:[[:space:]]*/, "", repo)
      repo=trim(repo)
      next
    }
    repo != "" && /^[[:space:]]*active:/ {
      active=$0
      sub(/^[[:space:]]*active:[[:space:]]*/, "", active)
      active=trim(active)
      status=(active == "false" || active == "no" || active == "0") ? "inactive" : "active"
      in_aliases=0
      next
    }
    repo != "" && /^[[:space:]]*status:/ {
      status=$0
      sub(/^[[:space:]]*status:[[:space:]]*/, "", status)
      status=trim(status)
      in_aliases=0
      next
    }
    repo != "" && /^[[:space:]]*aliases:[[:space:]]*$/ { in_aliases=1; next }
    repo != "" && in_aliases && /^[[:space:]]*-[[:space:]]*/ {
      alias=$0
      sub(/^[[:space:]]*-[[:space:]]*/, "", alias)
      aliases[trim(alias)]=1
      next
    }
    repo != "" && /^[[:space:]]*[A-Za-z_][A-Za-z0-9_-]*:/ { in_aliases=0; next }
    END { finish_record() }
  ' "$file"
}

coord_registry_canonical_repo_id() {
  local repo_id coord_dir repos_dir file manifest_repo status alias matches match_count found_alias legacy_file
  repo_id="$1"
  coord_dir="${2:-}"
  repos_dir="$(coord_registry_path "$coord_dir")"
  if ! coord_repo_id_is_valid "$repo_id"; then
    coord_die "invalid repo id '$repo_id'; use lowercase letters, digits, dots, underscores, and hyphens with no path separators"
  fi
  if [ ! -d "$repos_dir" ]; then
    legacy_file="$(coord_legacy_registry_path "$coord_dir")"
    if [ -f "$legacy_file" ]; then
      matches="$(coord_legacy_registry_matches "$repo_id" "$coord_dir")"
    else
      printf '%s\n' "$repo_id"
      return 0
    fi
  else
    matches=""
  while IFS= read -r file; do
    [ -n "$file" ] || continue
    manifest_repo="$(coord_repo_manifest_value "$file" repo_id || true)"
    [ -n "$manifest_repo" ] || manifest_repo="$(basename "$(dirname "$file")")"
    status="$(coord_repo_manifest_value "$file" status || true)"
    [ -n "$status" ] || status="active"
    if [ "$manifest_repo" = "$repo_id" ]; then
      matches="${matches}${manifest_repo}:canonical:${status}"$'\n'
      continue
    fi
    found_alias="no"
    while IFS= read -r alias; do
      [ "$alias" = "$repo_id" ] && found_alias="yes"
    done < <(coord_repo_manifest_list_values "$file" aliases)
    if [ "$found_alias" = "yes" ]; then
      matches="${matches}${manifest_repo}:alias:${status}"$'\n'
    fi
  done < <(find "$repos_dir" -mindepth 2 -maxdepth 2 -name REPO.md -type f 2>/dev/null | sort)
  fi

  match_count="$(printf '%s\n' "$matches" | sed '/^$/d' | wc -l | tr -d ' ')"
  if [ "$match_count" = "0" ]; then
    coord_die "repo id '$repo_id' is not registered in coordination registry: $repos_dir"
  fi
  if [ "$match_count" != "1" ]; then
    coord_die "repo id '$repo_id' is ambiguous in coordination registry"
  fi
  status="$(printf '%s' "$matches" | cut -d: -f3)"
  if [ "$status" != "active" ]; then
    if [ "$status" = "inactive" ]; then
      coord_die "repo id '$repo_id' is not active in coordination registry"
    fi
    coord_die "repo id '$repo_id' is retired in coordination registry"
  fi
  if [ "$(printf '%s' "$matches" | cut -d: -f2)" = "alias" ]; then
    coord_note "repo id '$repo_id' is an alias; update $(coord_impl_config_filename) to '$(printf '%s' "$matches" | cut -d: -f1)'"
  fi
  printf '%s\n' "$(printf '%s' "$matches" | cut -d: -f1)"
}

coord_resolve_repo_id() {
  local explicit coord_dir repo_id source canonical remote registry_err registry_status
  explicit="${1:-}"
  coord_dir="${2:-}"
  if [ -n "$explicit" ]; then
    repo_id="$explicit"
    source="--repo-id"
  elif [ -n "${PI_EN_COORD_REPO_ID:-}" ]; then
    repo_id="$PI_EN_COORD_REPO_ID"
    source="PI_EN_COORD_REPO_ID"
  else
    repo_id="$(coord_impl_config_value repo_id || true)"
    if [ -n "$repo_id" ]; then
      source="$(coord_impl_config_source || true)"
      [ -n "$source" ] || source="$(coord_impl_config_filename)"
    else
      remote="$(git remote get-url origin 2>/dev/null || true)"
      if [ -n "$remote" ]; then
        registry_err="$(mktemp "${TMPDIR:-/tmp}/pi-en-coord-remote.XXXXXX")" || coord_die "failed to create temporary file"
        if repo_id="$(coord_registry_repo_id_for_remote "$remote" "$coord_dir" 2>"$registry_err")" && [ -n "$repo_id" ]; then
          rm -f "$registry_err"
          source="coordination registry remote"
        else
          registry_status="$?"
          if [ -s "$registry_err" ]; then
            cat "$registry_err" >&2
            rm -f "$registry_err"
            return "$registry_status"
          fi
          rm -f "$registry_err"
          repo_id=""
        fi
      fi
      if [ -z "$repo_id" ] && repo_id="$(coord_infer_repo_id_from_remote 2>/dev/null || true)" && [ -n "$repo_id" ]; then
        source="git remote origin"
      elif [ -z "$repo_id" ]; then
        coord_die "missing repo id; pass --repo-id, set PI_EN_COORD_REPO_ID, add repo_id to $(coord_impl_config_filename), or configure git remote origin"
      fi
    fi
  fi
  canonical="$(coord_registry_canonical_repo_id "$repo_id" "$coord_dir")"
  [ -n "$canonical" ] || coord_die "empty repo id resolved from $source"
  printf '%s\n' "$canonical"
}

coord_resolve_coordination_remote() {
  local explicit remote
  explicit="${1:-}"
  if [ -n "$explicit" ]; then
    printf '%s\n' "$explicit"
  elif remote="$(coord_env_coordination_remote 2>/dev/null)" && [ -n "$remote" ]; then
    printf '%s\n' "$remote"
  else
    remote="$(coord_impl_config_value coordination_remote || true)"
    [ -n "$remote" ] || return 1
    coord_normalize_coordination_remote "$remote"
  fi
}

coord_default_root_for_project() {
  local project_root
  project_root="$(coord_project_root)"
  printf '%s\n' "$project_root/.pi-en/agent-remotes"
}

coord_default_root() {
  coord_default_root_for_project
}

coord_default_workspace() {
  basename "$(pwd -P)"
}

coord_default_dir_for_project() {
  local project_root
  project_root="$(coord_project_root)"
  printf '%s\n' "$project_root/.pi-en/coordination"
}

coord_project_local_dir() {
  local project_root
  project_root="${1:-}"
  [ -n "$project_root" ] || project_root="$(coord_project_root)"
  printf '%s\n' "$(coord_abs_lexical "$project_root/.pi-en/coordination")"
}

coord_resolve_project_path() {
  local candidate project_root
  candidate="$1"
  project_root="${2:-}"
  [ -n "$project_root" ] || project_root="$(coord_project_root)"
  case "$candidate" in
    /*) coord_abs_lexical "$candidate" ;;
    *) coord_abs_lexical "$project_root/$candidate" ;;
  esac
}

coord_require_project_local_coord_dir() {
  local candidate project_root actual expected source
  candidate="$1"
  project_root="${2:-}"
  source="${3:-coordination dir}"
  [ -n "$project_root" ] || project_root="$(coord_project_root)"
  actual="$(coord_resolve_project_path "$candidate" "$project_root")"
  expected="$(coord_project_local_dir "$project_root")"
  if [ "$actual" != "$expected" ]; then
    coord_die "$source must use the project-local coordination checkout: $expected"
  fi
  if [ "$(coord_abs "$actual")" != "$actual" ]; then
    coord_die "$source must be a real project-local coordination checkout, not a symlink: $expected"
  fi
  printf '%s\n' "$actual"
}

coord_default_dir() {
  if [ -n "${PI_EN_COORD_DIR:-}" ]; then
    printf '%s\n' "$PI_EN_COORD_DIR"
  else
    coord_default_dir_for_project
  fi
}

coord_default_agent() {
  if [ -n "${PI_EN_COORD_AGENT_ID:-}" ]; then
    printf '%s\n' "$PI_EN_COORD_AGENT_ID"
  elif [ -n "${USER:-}" ]; then
    printf '%s\n' "$USER"
  else
    printf '%s\n' "agent"
  fi
}

coord_default_role() {
  printf '%s\n' "${PI_EN_COORD_ROLE:-}"
}

coord_trim() {
  printf '%s' "$1" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//'
}

coord_effective_actor() {
  local agent role
  agent="$(coord_trim "$1")"
  role="$(coord_trim "$2")"

  if [ -n "$agent" ] && [ -n "$role" ]; then
    printf '%s/%s\n' "$agent" "$role"
  elif [ -n "$role" ]; then
    printf '%s\n' "$role"
  else
    printf '%s\n' "$agent"
  fi
}

coord_actor_email() {
  local actor local_part
  actor="$1"
  local_part="$(printf '%s' "$actor" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[[:space:]\/]+/+/g; s/[^a-z0-9._+%-]+/-/g; s/^[^a-z0-9]+//; s/[^a-z0-9]+$//')"
  if [ -z "$local_part" ]; then
    local_part="coordination"
  fi
  printf '%s@coordination.local\n' "$local_part"
}

coord_git_commit() {
  local actor email
  actor="$1"
  shift

  if [ -n "$actor" ]; then
    email="$(coord_actor_email "$actor")"
    git -c "user.name=$actor" -c "user.email=$email" commit "$@"
  else
    git commit "$@"
  fi
}

coord_template_dir() {
  local script_dir
  if [ -n "${PI_EN_COORD_TEMPLATE_DIR:-}" ]; then
    printf '%s\n' "$PI_EN_COORD_TEMPLATE_DIR"
    return
  fi
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
  printf '%s\n' "$(coord_abs "$script_dir/../pi-skill-templates/agent-coordination")"
}

coord_sanitize_path_part() {
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9._-]+/-/g; s/^-+//; s/-+$//; s/-+/-/g'
}

coord_project_id_prefix() {
  local value prefix
  value="$1"
  prefix="$(printf '%s' "$value" \
    | tr '[:lower:]' '[:upper:]' \
    | sed -E 's/[^A-Z0-9]+//g')"
  if [ -z "$prefix" ]; then
    prefix="ITEM"
  fi
  printf '%s\n' "$prefix"
}

coord_workspace_dir_key() {
  local coord_dir parent key
  coord_dir="$(coord_abs "$1")"
  parent="$(dirname "$coord_dir")"
  key="$(basename "$parent")"
  if [ -z "$key" ] || [ "$key" = "/" ]; then
    key="workspace"
  fi
  printf '%s\n' "$key"
}

coord_slug() {
  local slug
  slug="$(printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//; s/-+/-/g' \
    | cut -c1-60)"
  if [ -z "$slug" ]; then
    slug="item"
  fi
  printf '%s\n' "$slug"
}

coord_timestamp_id() {
  date -u +%Y%m%d-%H%M%S
}

coord_item_type_canonical() {
  local type canonical
  type="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  case "$type" in
    issue|issues)
      canonical="issue"
      ;;
    functional|functionals|functional-req|functional-reqs|functional_req|functional_reqs|functional-requirement|functional-requirements|functional_requirement|functional_requirements|frq|frqs)
      canonical="functional-requirement"
      ;;
    quality|qualities|quality-req|quality-reqs|quality_req|quality_reqs|quality-requirement|quality-requirements|quality_requirement|quality_requirements|qrq|qrqs)
      canonical="quality-requirement"
      ;;
    constraint|constraints|constraint-req|constraint-reqs|constraint_req|constraint_reqs|constraint-requirement|constraint-requirements|constraint_requirement|constraint_requirements|crq|crqs)
      canonical="constraint-requirement"
      ;;
    requirement|requirements|req|reqs)
      canonical="requirement"
      ;;
    todo|todos)
      canonical="todo"
      ;;
    decision|decisions|dec)
      canonical="decision"
      ;;
    note|notes)
      canonical="note"
      ;;
    *)
      canonical="$(coord_sanitize_path_part "$type")"
      [ -n "$canonical" ] || canonical="item"
      ;;
  esac
  printf '%s\n' "$canonical"
}

coord_item_type_code() {
  local type code
  type="$(coord_item_type_canonical "$1")"
  case "$type" in
    issue|issues)
      code="ISS"
      ;;
    functional-requirement|functional-requirements)
      code="FRQ"
      ;;
    quality-requirement|quality-requirements)
      code="QRQ"
      ;;
    constraint-requirement|constraint-requirements)
      code="CRQ"
      ;;
    requirement|requirements|req|reqs)
      code="REQ"
      ;;
    todo|todos)
      code="TODO"
      ;;
    decision|decisions|dec)
      code="DEC"
      ;;
    note|notes)
      code="NOTE"
      ;;
    *)
      code="$(printf '%s' "$type" \
        | tr '[:lower:]' '[:upper:]' \
        | sed -E 's/[^A-Z0-9]+//g' \
        | cut -c1-4)"
      [ -n "$code" ] || code="ITEM"
      ;;
  esac
  printf '%s\n' "$code"
}

coord_item_type_dir() {
  local type dir
  type="$(coord_item_type_canonical "$1")"
  case "$type" in
    issue|issues)
      dir="issues"
      ;;
    functional-requirement|functional-requirements|quality-requirement|quality-requirements|constraint-requirement|constraint-requirements|requirement|requirements|req|reqs)
      dir="requirements"
      ;;
    todo|todos)
      dir="todos"
      ;;
    decision|decisions|dec)
      dir="decisions"
      ;;
    note|notes)
      dir="notes"
      ;;
    *)
      dir="$(coord_sanitize_path_part "$type")"
      [ -n "$dir" ] || dir="items"
      case "$dir" in
        *s) ;;
        *) dir="${dir}s" ;;
      esac
      ;;
  esac
  printf '%s\n' "$dir"
}

coord_item_type_uses_issue_status_dirs() {
  local type
  type="$(coord_item_type_canonical "$1")"
  case "$type" in
    issue|issues)
      return 0
      ;;
  esac
  return 1
}

coord_category_canonical() {
  local type canonical
  type="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  case "$type" in
    feature|feature_request|feature-request|features|feature_requests|feature-requests)
      canonical="feature-request"
      ;;
    bug|bugs|defect|defects)
      canonical="bug"
      ;;
    task|tasks)
      canonical="task"
      ;;
    question|questions)
      canonical="question"
      ;;
    improvement|improvements|enhancement|enhancements)
      canonical="improvement"
      ;;
    *)
      canonical="$(coord_sanitize_path_part "$type")"
      ;;
  esac
  printf '%s\n' "$canonical"
}

coord_item_id_exists() {
  local candidate file id_value stem
  candidate="$1"
  while IFS= read -r file; do
    [ -n "$file" ] || continue
    id_value="$(coord_item_value "$file" id || true)"
    if [ "$id_value" = "$candidate" ]; then
      return 0
    fi
    stem="$(basename "$file")"
    stem="${stem%.yaml}"
    stem="${stem%.yml}"
    stem="${stem%.md}"
    if [ "$stem" = "$candidate" ]; then
      return 0
    fi
  done < <(coord_item_find_files)
  return 1
}

coord_next_item_id() {
  local key type timestamp code base n suffix candidate
  key="$1"
  type="$2"
  timestamp="$3"
  code="$(coord_item_type_code "$type")"
  base="$key-$code-$timestamp"
  n=1
  while [ "$n" -le 999 ]; do
    suffix="$(printf '%03d' "$n")"
    candidate="$base-$suffix"
    if ! coord_item_id_exists "$candidate"; then
      printf '%s\n' "$candidate"
      return 0
    fi
    n=$((n + 1))
  done
  coord_die "no unused item ID suffix below 1000 for $base"
}

coord_timestamp_iso() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

coord_remote_for() {
  local root workspace
  root="$1"
  workspace="$2"
  printf '%s/%s-coordination.git\n' "$root" "$workspace"
}

coord_external_local_remote_requires_alias() {
  local remote_path project_root default_remote_dir
  remote_path="$(coord_abs "$1")"
  project_root="$(coord_project_root)"
  default_remote_dir="$(coord_abs "$project_root/.pi-en/agent-remotes")"
  case "$remote_path" in
    "$default_remote_dir"|"$default_remote_dir"/*) return 1 ;;
  esac
  return 0
}

coord_external_local_remote_alias_name() {
  local remote_path base stem safe
  remote_path="$1"
  base="$(basename "$remote_path")"
  stem="${base%.git}"
  safe="$(coord_sanitize_path_part "$stem")"
  [ -n "$safe" ] || safe="coordination-remote"
  printf '%s.git\n' "$safe"
}

coord_bare_git_dir_is_valid() {
  local git_dir is_bare
  git_dir="$1"
  [ -d "$git_dir" ] || return 1
  is_bare="$(git --git-dir="$git_dir" rev-parse --is-bare-repository 2>/dev/null || true)"
  [ "$is_bare" = "true" ]
}

coord_ensure_external_local_coordination_remote_alias() {
  local remote_path project_root alias_dir alias_name alias_path link_target link_abs
  remote_path="$(coord_abs "$1")"
  if ! coord_external_local_remote_requires_alias "$remote_path"; then
    printf '%s\n' "$remote_path"
    return
  fi
  coord_bare_git_dir_is_valid "$remote_path" \
    || coord_die "external coordination remote must be an existing bare Git repo: $remote_path"

  project_root="$(coord_project_root)"
  alias_dir="$(coord_abs "$project_root/.pi-en/agent-remotes")"
  alias_name="$(coord_external_local_remote_alias_name "$remote_path")"
  alias_path="$alias_dir/$alias_name"
  coord_ensure_operational_root_excluded "$alias_dir"
  mkdir -p "$alias_dir"

  if [ -L "$alias_path" ]; then
    link_target="$(readlink "$alias_path")"
    case "$link_target" in
      /*) link_abs="$(coord_abs "$link_target")" ;;
      *) link_abs="$(coord_abs "$(dirname "$alias_path")/$link_target")" ;;
    esac
    [ "$link_abs" = "$remote_path" ] \
      || coord_die "coordination remote alias collision: $alias_path points to $link_abs, not $remote_path"
    ln -sfn "$remote_path" "$alias_path"
  elif [ -e "$alias_path" ]; then
    coord_die "coordination remote alias collision: $alias_path already exists and is not an alias for $remote_path"
  else
    ln -s "$remote_path" "$alias_path"
  fi

  printf '%s\n' "$alias_path"
}

coord_local_remote_url_for_clone() {
  local coord_dir remote_path rel project_root default_coord_dir default_remote_dir remote_base
  coord_dir="$(coord_abs "$1")"
  remote_path="$(coord_abs_lexical "$2")"
  project_root="$(coord_project_root)"
  default_coord_dir="$(coord_abs "$project_root/.pi-en/coordination")"
  default_remote_dir="$(coord_abs "$project_root/.pi-en/agent-remotes")"

  if [ "$coord_dir" = "$default_coord_dir" ]; then
    case "$remote_path" in
      "$default_remote_dir"/*)
        remote_base="$(basename "$remote_path")"
        if [ -n "$remote_base" ] && [ "$remote_base" != "." ] && [ "$remote_base" != ".." ]; then
          printf '../agent-remotes/%s\n' "$remote_base"
          return
        fi
        ;;
    esac
  fi

  if rel="$(realpath -m --relative-to="$coord_dir" "$remote_path" 2>/dev/null)"; then
    case "$rel" in
      /*|'') printf '%s\n' "$remote_path" ;;
      *) printf '%s\n' "$rel" ;;
    esac
  else
    printf '%s\n' "$remote_path"
  fi
}

coord_ensure_operational_root_excluded() {
  local target_dir project_root target_abs pi_en_root exclude_path
  target_dir="$1"
  project_root="$(coord_project_root)"
  target_abs="$(coord_abs "$target_dir")"
  pi_en_root="$(coord_abs "$project_root/.pi-en")"

  case "$target_abs" in
    "$pi_en_root"|"$pi_en_root"/*) ;;
    *) return 0 ;;
  esac

  exclude_path="$(git -C "$project_root" rev-parse --git-path info/exclude 2>/dev/null || true)"
  [ -n "$exclude_path" ] || return 0
  mkdir -p "$(dirname "$exclude_path")"
  touch "$exclude_path"
  if ! grep -Fxq '/.pi-en/' "$exclude_path"; then
    printf '/.pi-en/\n' >>"$exclude_path"
  fi
}

coord_is_coord_repo() {
  local dir
  dir="$1"
  [ -d "$dir/.git" ] \
    && [ -f "$dir/AGENTS.md" ] \
    && [ -f "$dir/docs/SYNC_PROTOCOL.md" ] \
    && [ -f "$dir/docs/ITEM_FORMAT.md" ]
}

coord_resolve_dir() {
  local candidate git_root project_root
  candidate="${1:-}"
  if [ -z "$candidate" ] && [ -n "${PI_EN_COORD_DIR:-}" ]; then
    candidate="$PI_EN_COORD_DIR"
  fi
  if [ -z "$candidate" ]; then
    git_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
    if [ -n "$git_root" ] && coord_is_coord_repo "$git_root"; then
      coord_abs "$git_root"
      return
    fi
    project_root="$(coord_project_root)"
    candidate="$project_root/.pi-en/coordination"
  fi
  [ -d "$candidate" ] || coord_die "coordination dir not found: $candidate"
  candidate="$(coord_abs "$candidate")"
  [ -d "$candidate/.git" ] || coord_die "not a Git repo: $candidate"
  printf '%s\n' "$candidate"
}

coord_git_config_defaults() {
  git config pull.rebase true
  git config rebase.autoStash true
}

coord_install_template() {
  local source_name target template_dir target_dir
  source_name="$1"
  target="$2"
  template_dir="$(coord_template_dir)"
  [ -f "$template_dir/$source_name" ] \
    || coord_die "missing template: $template_dir/$source_name"
  target_dir="$(dirname "$target")"
  mkdir -p "$target_dir"
  cp "$template_dir/$source_name" "$target"
}

coord_git_has_head() {
  git rev-parse --verify HEAD >/dev/null 2>&1
}

coord_git_has_staged_changes() {
  ! git diff --cached --quiet --exit-code
}

coord_git_has_worktree_changes() {
  ! git diff --quiet --exit-code || [ -n "$(git ls-files --others --exclude-standard)" ]
}

coord_validate_subject() {
  local subject
  subject="$1"
  if [ "${#subject}" -gt 72 ]; then
    coord_die "commit subject exceeds 72 characters: $subject"
  fi
}

coord_commit_all_if_changed() {
  local message actor
  message="$1"
  actor="${2:-}"
  coord_validate_subject "$message"
  git add -A
  if coord_git_has_staged_changes; then
    coord_git_commit "$actor" -m "$message"
    return 0
  fi
  return 1
}

coord_pull_rebase() {
  if git remote get-url origin >/dev/null 2>&1; then
    git pull --rebase --autostash "$@"
  else
    coord_note "no origin remote configured; skipping pull"
  fi
}

coord_repo_path() {
  local path
  path="$1"
  realpath -m --relative-to="$(pwd -P)" "$path" 2>/dev/null || printf '%s\n' "$path"
}

coord_move_issue_item_to_status() {
  local item_path target_status target_path
  item_path="$1"
  target_status="$2"
  target_path="$item_path"

  case "$item_path" in
    issues/open/*)
      target_path="issues/$target_status/${item_path#issues/open/}"
      ;;
    issues/blocked/*)
      target_path="issues/$target_status/${item_path#issues/blocked/}"
      ;;
    issues/done/*)
      target_path="issues/$target_status/${item_path#issues/done/}"
      ;;
    issues/closed/*)
      target_path="issues/$target_status/${item_path#issues/closed/}"
      ;;
    */issues/open/*)
      target_path="${item_path/\/issues\/open\//\/issues\/$target_status\/}"
      ;;
    */issues/blocked/*)
      target_path="${item_path/\/issues\/blocked\//\/issues\/$target_status\/}"
      ;;
    */issues/done/*)
      target_path="${item_path/\/issues\/done\//\/issues\/$target_status\/}"
      ;;
    */issues/closed/*)
      target_path="${item_path/\/issues\/closed\//\/issues\/$target_status\/}"
      ;;
  esac

  if [ "$target_path" != "$item_path" ]; then
    mkdir -p "$(dirname "$target_path")"
    if git ls-files --error-unmatch -- "$item_path" >/dev/null 2>&1; then
      git mv "$item_path" "$target_path"
    else
      mv "$item_path" "$target_path"
    fi
    item_path="$target_path"
  fi

  printf '%s\n' "$item_path"
}

coord_item_flag_true() {
  local file key value
  file="$1"
  key="$2"
  value="$(coord_item_value "$file" "$key" | tr '[:upper:]' '[:lower:]')"
  case "$value" in
    true|yes|1)
      return 0
      ;;
  esac
  return 1
}

coord_yaml_quote() {
  local value
  value="$(printf '%s' "$1" | sed "s/'/''/g")"
  printf "'%s'" "$value"
}

coord_yaml_scalar() {
  local value
  value="$1"
  if [ -z "$value" ]; then
    printf 'null'
  elif printf '%s' "$value" | grep -Eq '^[A-Za-z0-9_.@/+:-]+$'; then
    printf '%s' "$value"
  else
    coord_yaml_quote "$value"
  fi
}

coord_yaml_unquote() {
  local value first last
  value="$(coord_trim "$1")"
  case "$value" in
    ""|null|Null|NULL|~)
      printf '\n'
      return
      ;;
  esac
  first="${value:0:1}"
  last="${value: -1}"
  if [ "$first" = "'" ] && [ "$last" = "'" ] && [ "${#value}" -ge 2 ]; then
    value="${value:1:${#value}-2}"
    value="$(printf '%s' "$value" | sed "s/''/'/g")"
  elif [ "$first" = '"' ] && [ "$last" = '"' ] && [ "${#value}" -ge 2 ]; then
    value="${value:1:${#value}-2}"
  fi
  printf '%s\n' "$value"
}

coord_frontmatter_value() {
  local file key value
  file="$1"
  key="$2"
  value="$(awk -v key="$key" '
    NR == 1 && $0 == "---" { fm = 1; next }
    fm && $0 == "---" { exit }
    fm && index($0, key ":") == 1 {
      sub("^[^:]+:[[:space:]]*", "")
      print
      exit
    }
  ' "$file")"
  coord_yaml_unquote "$value"
}

coord_item_value() {
  local file key value
  file="$1"
  key="$2"
  value="$(awk -v key="$key" '
    NR == 1 && $0 == "---" { fm = 1; next }
    fm && $0 == "---" { exit }
    fm && index($0, key ":") == 1 {
      sub("^[^:]+:[[:space:]]*", "")
      print
      exit
    }
    NR == 1 && $0 != "---" { top = 1 }
    top && index($0, key ":") == 1 {
      sub("^[^:]+:[[:space:]]*", "")
      print
      exit
    }
  ' "$file")"
  coord_yaml_unquote "$value"
}

coord_metadata_item_key() {
  local file value
  file="$1"
  value=""
  if [ -f "$file" ]; then
    value="$(coord_frontmatter_value "$file" item_key || true)"
  fi
  printf '%s\n' "$value"
}

coord_metadata_value() {
  local file key value
  file="$1"
  key="$2"
  value=""
  if [ -f "$file" ]; then
    value="$(coord_frontmatter_value "$file" "$key" || true)"
  fi
  printf '%s\n' "$value"
}

coord_has_project_root_layout() {
  [ -f PROJECT.md ] && {
    [ -d issues ] || [ -d requirements ] || [ -d todos ] \
      || [ -d decisions ] || [ -d notes ]
  }
}

coord_write_root_items_by_default() {
  coord_has_project_root_layout
}

coord_set_frontmatter() {
  local file tmp sep keys values pair key value
  file="$1"
  shift
  sep=$(printf '\037')
  keys=""
  values=""
  for pair in "$@"; do
    key="${pair%%=*}"
    value="${pair#*=}"
    keys="${keys}${sep}${key}"
    values="${values}${sep}${value}"
  done
  keys="${keys#${sep}}"
  values="${values#${sep}}"
  tmp="$(mktemp)"
  awk -v keys="$keys" -v values="$values" -v sep="$sep" '
    BEGIN {
      n = split(keys, key_list, sep)
      split(values, value_list, sep)
      for (i = 1; i <= n; i++) {
        wanted[key_list[i]] = value_list[i]
        found[key_list[i]] = 0
      }
    }
    NR == 1 && $0 == "---" {
      in_fm = 1
      print
      next
    }
    in_fm && $0 == "---" {
      for (i = 1; i <= n; i++) {
        key = key_list[i]
        if (!found[key]) {
          print key ": " wanted[key]
        }
      }
      in_fm = 0
      print
      next
    }
    in_fm {
      for (i = 1; i <= n; i++) {
        key = key_list[i]
        if (index($0, key ":") == 1) {
          print key ": " wanted[key]
          found[key] = 1
          next
        }
      }
      print
      next
    }
    { print }
  ' "$file" >"$tmp"
  mv "$tmp" "$file"
}

coord_set_item_values() {
  local file tmp sep keys values pair key value
  file="$1"
  shift
  sep=$(printf '\037')
  keys=""
  values=""
  for pair in "$@"; do
    key="${pair%%=*}"
    value="${pair#*=}"
    keys="${keys}${sep}${key}"
    values="${values}${sep}${value}"
  done
  keys="${keys#${sep}}"
  values="${values#${sep}}"
  tmp="$(mktemp)"
  awk -v keys="$keys" -v values="$values" -v sep="$sep" '
    BEGIN {
      n = split(keys, key_list, sep)
      split(values, value_list, sep)
      for (i = 1; i <= n; i++) {
        wanted[key_list[i]] = value_list[i]
        found[key_list[i]] = 0
      }
    }
    !inserted && ($0 == "current:" || $0 == "events:" || $0 == "messages:") {
      for (i = 1; i <= n; i++) {
        key = key_list[i]
        if (!found[key]) {
          print key ": " wanted[key]
          found[key] = 1
        }
      }
      inserted = 1
    }
    {
      for (i = 1; i <= n; i++) {
        key = key_list[i]
        if (index($0, key ":") == 1) {
          print key ": " wanted[key]
          found[key] = 1
          next
        }
      }
      print
    }
    END {
      if (!inserted) {
        for (i = 1; i <= n; i++) {
          key = key_list[i]
          if (!found[key]) {
            print key ": " wanted[key]
          }
        }
      }
    }
  ' "$file" >"$tmp"
  mv "$tmp" "$file"
}

coord_set_current_pointers() {
  local file event_id message_id tmp
  file="$1"
  event_id="$2"
  message_id="$3"
  tmp="$(mktemp)"
  awk -v event_id="$event_id" -v message_id="$message_id" '
    /^current:[[:space:]]*$/ {
      in_current = 1
      saw_current = 1
      saw_event = 0
      saw_message = 0
      print
      next
    }
    in_current && /^  event:/ {
      print "  event: " event_id
      saw_event = 1
      next
    }
    in_current && /^  message:/ {
      print "  message: " message_id
      saw_message = 1
      next
    }
    in_current && /^[^[:space:]]/ {
      if (!saw_event) print "  event: " event_id
      if (!saw_message) print "  message: " message_id
      in_current = 0
    }
    !saw_current && ($0 == "events:" || $0 == "messages:") {
      print "current:"
      print "  event: " event_id
      print "  message: " message_id
      saw_current = 1
    }
    { print }
    END {
      if (in_current) {
        if (!saw_event) print "  event: " event_id
        if (!saw_message) print "  message: " message_id
      } else if (!saw_current) {
        print "current:"
        print "  event: " event_id
        print "  message: " message_id
      }
    }
  ' "$file" >"$tmp"
  mv "$tmp" "$file"
}

coord_next_event_id() {
  local file
  file="$1"
  awk '
    /^[[:space:]]*- id: evt-[0-9]+/ {
      value = $0
      sub(/^.*evt-/, "", value)
      sub(/[^0-9].*$/, "", value)
      n = value + 0
      if (n > max) max = n
    }
    END { printf "evt-%04d\n", max + 1 }
  ' "$file"
}

coord_message_id_for_event() {
  local event_id number
  event_id="$1"
  number="${event_id#evt-}"
  printf 'msg-%s\n' "$number"
}

coord_write_implementation_ref_yaml() {
  local indent ref repo rest branch commit
  indent="$1"
  ref="$2"

  repo="${ref%%:*}"
  if [ "$repo" = "$ref" ]; then
    coord_die "invalid implementation ref, expected repo:branch@full-commit: $ref"
  fi
  rest="${ref#*:}"
  branch="${rest%@*}"
  commit="${rest##*@}"
  if [ "$branch" = "$rest" ]; then
    coord_die "invalid implementation ref, expected repo:branch@full-commit: $ref"
  fi
  if [ -z "$repo" ] || [ -z "$branch" ] || [ -z "$commit" ]; then
    coord_die "invalid implementation ref, expected repo:branch@full-commit: $ref"
  fi
  if ! [[ "$commit" =~ ^[0-9A-Fa-f]{40}$ ]]; then
    coord_die "implementation ref commit must be a full 40-character hash: $ref"
  fi

  printf '%s- repo: %s\n' "$indent" "$(coord_yaml_scalar "$repo")"
  printf '%s  branch: %s\n' "$indent" "$(coord_yaml_scalar "$branch")"
  printf '%s  commit: %s\n' "$indent" "$(coord_yaml_scalar "$commit")"
}

coord_append_item_event_message() {
  local file event_id event_type timestamp agent_id role message_id body tmp event_tmp message_tmp ref
  file="$1"
  event_id="$2"
  event_type="$3"
  timestamp="$4"
  agent_id="$5"
  role="$6"
  message_id="$7"
  body="$8"
  shift 8

  event_tmp="$(mktemp)"
  message_tmp="$(mktemp)"
  tmp="$(mktemp)"

  {
    printf '  - id: %s\n' "$event_id"
    printf '    type: %s\n' "$event_type"
    printf '    at: %s\n' "$timestamp"
    printf '    actor:\n'
    printf '      id: %s\n' "$(coord_yaml_scalar "$agent_id")"
    printf '      role: %s\n' "$(coord_yaml_scalar "$role")"
    printf '    message: %s\n' "$message_id"
    if [ "$event_type" = "claimed" ]; then
      printf '    owner: %s\n' "$(coord_yaml_scalar "$agent_id")"
    fi
    if [ "$#" -gt 0 ]; then
      printf '    implementation_refs:\n'
      for ref in "$@"; do
        [ -n "$ref" ] || continue
        coord_write_implementation_ref_yaml "      " "$ref"
      done
    fi
  } >"$event_tmp"

  {
    printf '  - id: %s\n' "$message_id"
    printf '    event: %s\n' "$event_id"
    printf '    body: |-\n'
    if [ -n "$body" ]; then
      printf '%s\n' "$body" | sed -e 's/^/      /' -e 's/^      $//'
    else
      printf '      \n'
    fi
  } >"$message_tmp"

  awk -v event_file="$event_tmp" -v message_file="$message_tmp" '
    /^messages:[[:space:]]*$/ && !inserted_event {
      while ((getline line < event_file) > 0) print line
      close(event_file)
      inserted_event = 1
    }
    { print }
    END {
      if (!inserted_event) {
        print "events:"
        while ((getline line < event_file) > 0) print line
        close(event_file)
        print "messages:"
      }
      while ((getline line < message_file) > 0) print line
      close(message_file)
    }
  ' "$file" >"$tmp"

  mv "$tmp" "$file"
  rm -f "$event_tmp" "$message_tmp"
}

coord_append_activity() {
  local file timestamp agent message
  file="$1"
  timestamp="$2"
  agent="$3"
  message="$4"
  message="$(printf '%s' "$message" | tr '\n' ' ')"
  if ! grep -q '^## Activity$' "$file"; then
    printf '\n## Activity\n' >>"$file"
  fi
  printf '\n- %s %s: %s\n' "$timestamp" "$agent" "$message" >>"$file"
}

coord_item_find_files() {
  local roots=() root
  for root in issues requirements todos decisions notes; do
    if [ -e "$root" ]; then
      roots+=("$root")
    fi
  done
  if [ -d repos ]; then
    while IFS= read -r root; do
      [ -n "$root" ] && roots+=("$root")
    done < <(find repos -mindepth 2 -maxdepth 2 -type d \
      \( -name issues -o -name requirements -o -name todos -o -name decisions -o -name notes \) \
      2>/dev/null | sort)
  fi
  [ "${#roots[@]}" -gt 0 ] || return 0

  find "${roots[@]}" \
    -type f \
    \( -name '*.yaml' -o -name '*.yml' -o -name '*.md' \) \
    2>/dev/null | sort
}

coord_find_item() {
  local query match_count matches file id_value
  query="$1"
  if [ -f "$query" ]; then
    coord_abs "$query"
    return
  fi

  matches=""
  while IFS= read -r file; do
    [ -n "$file" ] || continue
    case "$(basename "$file")" in
      "$query"|"$query".md|"$query".yaml|"$query".yml|"$query"-*)
        matches="${matches}${file}"$'\n'
        continue
        ;;
    esac
    id_value="$(coord_item_value "$file" id || true)"
    if [ "$id_value" = "$query" ]; then
      matches="${matches}${file}"$'\n'
    fi
  done < <(coord_item_find_files)

  match_count="$(printf '%s' "$matches" | sed '/^$/d' | wc -l | tr -d ' ')"
  if [ "$match_count" = "0" ]; then
    coord_die "item not found: $query"
  fi

  if [ "$match_count" != "1" ]; then
    printf 'pi-en-coord: multiple items match %s:\n%s' "$query" "$matches" >&2
    exit 1
  fi
  printf '%s' "$matches" | sed '/^$/d' | head -n 1
}

coord_issue_lifecycle_scope_repo_id() {
  local repo_id_opt project_dir coord_dir
  repo_id_opt="${1:-}"
  project_dir="${2:-}"
  coord_dir="${3:-}"
  [ -n "$project_dir" ] || project_dir="$(coord_project_root)"
  [ -n "$coord_dir" ] || coord_dir="$(pwd -P)"
  (cd "$project_dir" && coord_resolve_repo_id "$repo_id_opt" "$coord_dir")
}

coord_guard_issue_lifecycle_scope() {
  local item_path repo_id command rel
  item_path="$1"
  repo_id="$2"
  command="${3:-lifecycle command}"
  rel="$(coord_repo_path "$item_path")"

  case "$rel" in
    "repos/$repo_id/issues/"*)
      return 0
      ;;
    issues/*)
      coord_die "$command refuses root issue outside repo scope '$repo_id': $rel"
      ;;
    repos/*/issues/*)
      coord_die "$command refuses issue outside repo scope '$repo_id': $rel"
      ;;
    *)
      coord_die "$command requires an issue under repos/$repo_id/issues: $rel"
      ;;
  esac
}

coord_find_issue_lifecycle_item() {
  local query repo_id_opt project_dir coord_dir command repo_id root matches file id_value match_count found
  query="$1"
  repo_id_opt="${2:-}"
  project_dir="${3:-}"
  coord_dir="${4:-}"
  command="${5:-lifecycle command}"

  if [ ! -d repos ]; then
    coord_find_item "$query"
    return
  fi

  repo_id="$(coord_issue_lifecycle_scope_repo_id "$repo_id_opt" "$project_dir" "$coord_dir")"
  [ -n "$repo_id" ] || coord_die "failed to resolve repo scope for $command"

  if [ -f "$query" ]; then
    found="$(coord_repo_path "$(coord_abs "$query")")"
    coord_guard_issue_lifecycle_scope "$found" "$repo_id" "$command"
    printf '%s\n' "$(coord_abs "$found")"
    return
  fi

  root="repos/$repo_id/issues"
  [ -d "$root" ] || coord_die "repo scope has no issue directory: $root"
  matches=""
  while IFS= read -r file; do
    [ -n "$file" ] || continue
    case "$(basename "$file")" in
      "$query"|"$query".md|"$query".yaml|"$query".yml|"$query"-*)
        matches="${matches}${file}"$'\n'
        continue
        ;;
    esac
    id_value="$(coord_item_value "$file" id || true)"
    if [ "$id_value" = "$query" ]; then
      matches="${matches}${file}"$'\n'
    fi
  done < <(find "$root" -type f \( -name '*.yaml' -o -name '*.yml' -o -name '*.md' \) 2>/dev/null | sort)

  match_count="$(printf '%s' "$matches" | sed '/^$/d' | wc -l | tr -d ' ')"
  if [ "$match_count" = "0" ]; then
    if found="$(coord_find_item "$query" 2>/dev/null)" && [ -n "$found" ]; then
      coord_guard_issue_lifecycle_scope "$(coord_repo_path "$found")" "$repo_id" "$command"
    fi
    coord_die "item not found in repo scope '$repo_id': $query"
  fi

  if [ "$match_count" != "1" ]; then
    printf 'pi-en-coord: multiple items match %s in repo scope %s:\n%s' "$query" "$repo_id" "$matches" >&2
    exit 1
  fi
  printf '%s' "$matches" | sed '/^$/d' | head -n 1
}
