#!/bin/bash

set -euo pipefail

DATA_DIR="${DATA_DIR:-../labfiles-3-26}"
SUBJECTS=("Цирковое_Дело" "Пересдачеведение")
GROUPS_DIR="students/groups"
NOTES_DIR="students/general/notes"

usage() {
    cat <<EOF
Usage: $0 [--data-dir <path>] <command> [args]

Commands:
  longest <group>           Student(s) with longest surname
  missed  <group>           Missed lesson numbers per student
  avg     <group> [...]     Average attendance for group(s)
  dossier <name>            Show student dossier
  delete  <name>            Delete dossier only (with confirmation)
  help                      Show this help
EOF
}

die()  { echo "Error: $*" >&2; exit 1; }

get_surname() {
    echo "$1" | sed 's/[A-Z]*$//'
}

check_group_file() {
    local gfile="$DATA_DIR/$GROUPS_DIR/$1"
    [[ -f "$gfile" ]] || die "Group file not found: $1"
    echo "$gfile"
}

# FR-01: longest surname
cmd_longest() {
    local group="${1:-}"
    [[ -n "$group" ]] || die "Usage: longest <group>"
    local gfile
    gfile=$(check_group_file "$group")

    local max_len=0
    local -a winners=()

    while IFS= read -r name || [[ -n "$name" ]]; do
        name="${name//$'\r'/}"
        [[ -z "$name" ]] && continue
        local sur len
        sur=$(get_surname "$name")
        len=${#sur}
        if (( len > max_len )); then
            max_len=$len
            winners=("$name")
        elif (( len == max_len )); then
            winners+=("$name")
        fi
    done < "$gfile"

    (( ${#winners[@]} > 0 )) || die "No students in group $group"

    echo "Group: $group"
    echo "Max surname length: $max_len"
    if (( ${#winners[@]} == 1 )); then
        echo "Student: ${winners[0]}  (surname: $(get_surname "${winners[0]}"))"
    else
        echo "Students with longest surname (${#winners[@]}):"
        for w in "${winners[@]}"; do
            echo "  $w  (surname: $(get_surname "$w"))"
        done
    fi
}

# FR-02: missed lessons
cmd_missed() {
    local group="${1:-}"
    [[ -n "$group" ]] || die "Usage: missed <group>"

    local -a att_files=()
    for subj in "${SUBJECTS[@]}"; do
        local f="$DATA_DIR/$subj/${group}-attendance"
        [[ -f "$f" ]] && att_files+=("$f")
    done
    (( ${#att_files[@]} > 0 )) || die "No attendance files for group $group"

    echo "Group: $group"
    echo "Subjects found: ${#att_files[@]}"

    local -A seen=()
    local -a order=()

    for f in "${att_files[@]}"; do
        while IFS= read -r line || [[ -n "$line" ]]; do
            line="${line//$'\r'/}"
            [[ -z "$line" ]] && continue
            local name="${line%% *}"
            if [[ -z "${seen[$name]+x}" ]]; then
                seen[$name]=1
                order+=("$name")
            fi
        done < "$f"
    done

    for name in "${order[@]}"; do
        echo "Student: $name"
        local any=0
        for f in "${att_files[@]}"; do
            local subj record bits
            subj=$(basename "$(dirname "$f")")
            record=$(grep -E "^${name} " "$f" 2>/dev/null || true)
            if [[ -z "$record" ]]; then
                echo "  [$subj]: no record"
                continue
            fi
            bits="${record#* }"
            bits="${bits// /}"
            local missed=() i
            for (( i=0; i<${#bits}; i++ )); do
                [[ "${bits:i:1}" == "0" ]] && missed+=("$((i+1))")
            done
            if (( ${#missed[@]} > 0 )); then
                any=1
                echo "  [$subj]: missed lessons: ${missed[*]}"
            else
                echo "  [$subj]: no misses"
            fi
        done
        (( any == 0 )) && echo "  (perfect attendance)"
        echo
    done
}

# FR-03: average attendance
cmd_avg() {
    (( $# >= 1 )) || die "Usage: avg <group> [group...]"

    echo "Average attendance report"

    local total_present=0 total_lessons=0

    for group in "$@"; do
        local g_present=0 g_lessons=0 found=0
        for subj in "${SUBJECTS[@]}"; do
            local f="$DATA_DIR/$subj/${group}-attendance"
            [[ -f "$f" ]] || continue
            found=1
            while IFS= read -r line || [[ -n "$line" ]]; do
                line="${line//$'\r'/}"
                [[ -z "$line" ]] && continue
                local bits="${line#* }"
                bits="${bits// /}"
                local ones
                ones=$(echo "$bits" | tr -cd '1' | wc -c)
                g_present=$((g_present + ones))
                g_lessons=$((g_lessons + ${#bits}))
            done < "$f"
        done

        if (( found == 0 )); then
            echo "Group $group: no attendance data"
            continue
        fi
        if (( g_lessons == 0 )); then
            echo "Group $group: empty data"
            continue
        fi

        local pct
        pct=$(awk -v p="$g_present" -v t="$g_lessons" 'BEGIN{printf "%.2f", p/t*100}')
        echo "Group $group: ${pct}%  (${g_present} present / ${g_lessons} total marks)"
        total_present=$((total_present + g_present))
        total_lessons=$((total_lessons + g_lessons))
    done

    if (( total_lessons > 0 )); then
        echo "----------------------------------------"
        local overall
        overall=$(awk -v p="$total_present" -v t="$total_lessons" 'BEGIN{printf "%.2f", p/t*100}')
        echo "Overall: ${overall}%  (${total_present}/${total_lessons})"
    fi
}

# FR-04: dossier
cmd_dossier() {
    local query="${1:-}"
    [[ -n "$query" ]] || die "Usage: dossier <name>"

    local first
    first=$(echo "${query:0:1}" | tr '[:lower:]' '[:upper:]')
    local notes_file="$DATA_DIR/$NOTES_DIR/${first}Names.log"
    [[ -f "$notes_file" ]] || die "Notes file not found for '$first'"

    local found=0 in_block=0 current=""
    local -a block=()

    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line//$'\r'/}"
        if [[ "$line" =~ ^=+\ *$ ]]; then
            if (( in_block )); then
                if [[ "$current" == "$query" ]]; then
                    found=1
                    echo "Dossier for: $current"
                    echo "----------------------------------------"
                    printf '%s\n' "${block[@]}"
                    echo "----------------------------------------"
                fi
                in_block=0
                block=()
                current=""
            fi
            in_block=1
            continue
        fi
        if (( in_block )); then
            if [[ -z "$current" ]]; then
                current="${line%%[[:space:]]*}"
            else
                block+=("$line")
            fi
        fi
    done < "$notes_file"

    if (( in_block )) && [[ "$current" == "$query" ]]; then
        found=1
        echo "Dossier for: $current"
        echo "----------------------------------------"
        printf '%s\n' "${block[@]}"
        echo "----------------------------------------"
    fi

    if (( found == 0 )); then
        echo "No dossier found for: $query"
    fi
}

# FR-05: delete dossier
cmd_delete() {
    local name="${1:-}"
    [[ -n "$name" ]] || die "Usage: delete <name>"

    local first
    first=$(echo "${name:0:1}" | tr '[:lower:]' '[:upper:]')
    local notes_file="$DATA_DIR/$NOTES_DIR/${first}Names.log"
    [[ -f "$notes_file" ]] || die "Notes file not found for '$first'"

    if ! grep -q "^${name}$" "$notes_file"; then
        die "Dossier for '$name' not found in $notes_file"
    fi

    echo "DELETE DOSSIER CONFIRMATION"
    echo "Student : $name"
    echo "File    : $notes_file"
    echo
    echo "A backup (.bak) will be created."
    echo
    read -r -p "Type 'YES' to confirm: " confirm
    if [[ "$confirm" != "YES" ]]; then
        echo "Aborted. No changes made."
        return 0
    fi

    cp -a "$notes_file" "${notes_file}.bak"

    awk -v target="$name" '
        BEGIN { skip=0; pending=0 }
        /^=+[ ]*$/ {
            if (skip) { skip=0; next }
            pending=1
            sep=$0
            next
        }
        pending==1 {
            if ($0 == target) {
                skip=1
                pending=0
                next
            } else {
                print sep
                print
                pending=0
                next
            }
        }
        skip==0 { print }
    ' "$notes_file" > "${notes_file}.tmp" && mv "${notes_file}.tmp" "$notes_file"

    echo "[OK] Dossier removed (backup: ${notes_file}.bak)"
}

# main
main() {
    (( $# == 0 )) && { usage; exit 0; }

    case "$1" in
        -h|--help|help)
            usage
            exit 0
            ;;
        --data-dir)
            shift
            DATA_DIR="${1:-}"
            [[ -n "$DATA_DIR" ]] || die "--data-dir requires a path"
            shift
            ;;
    esac

    local cmd="${1:-}"
    shift || true

    case "$cmd" in
        longest) cmd_longest "$@" ;;
        missed)  cmd_missed  "$@" ;;
        avg)     cmd_avg     "$@" ;;
        dossier) cmd_dossier "$@" ;;
        delete)  cmd_delete  "$@" ;;
        ""|help) usage ;;
        *) die "Unknown command: $cmd" ;;
    esac
}

main "$@"
