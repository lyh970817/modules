#!/usr/bin/env bash
set -euo pipefail

expected="$1"
prefix="$2"
read -r -a declared_parts <<< "$3"
eval "bin_parts=($4)"
eval "n_bin_parts=($5)"
eval "id_parts=($6)"
process_name="$7"

[[ "$expected" =~ ^[1-9][0-9]*$ ]] || { echo "expected_parts must be a positive integer" >&2; exit 1; }
for family in bin_parts n_bin_parts id_parts declared_parts; do
    declare -n values="$family"
    [[ "${#values[@]}" -eq "$expected" ]] || { echo "$family must contain exactly expected_parts entries" >&2; exit 1; }
done

declare -A bins n_bins ids declared
for part in "${declared_parts[@]}"; do
    [[ "$part" =~ ^[1-9][0-9]*$ ]] || { echo "part_numbers must be positive integers" >&2; exit 1; }
    [[ -z "${declared[$part]:-}" ]] || { echo "duplicate declared part $part" >&2; exit 1; }
    declared["$part"]=1
done

index_family() {
    local family_name="$1" suffix="$2" map_name="$3" file key token total
    declare -n family="$family_name" target="$map_name"
    for file in "${family[@]}"; do
        [[ "$file" == *.part_*_*.grm.* ]] || { echo "invalid $family_name filename: $file" >&2; exit 1; }
        token="${file##*.part_}"
        token="${token%%.grm.*}"
        total="${token%%_*}"
        key="${token#*_}"
        [[ "$total" -eq "$expected" ]] || { echo "filename expected-parts mismatch: $file" >&2; exit 1; }
        [[ -z "${target[$key]:-}" ]] || { echo "duplicate $family_name part $key" >&2; exit 1; }
        target["$key"]="$file"
    done
}
index_family bin_parts 'bin' bins
index_family n_bin_parts 'N\.bin' n_bins
index_family id_parts 'id' ids

: > "${prefix}.grm.bin"
: > "${prefix}.grm.N.bin"
: > "${prefix}.grm.id"
previous_ids=0
declare -A seen_ids
for ((part=1; part<=expected; part++)); do
    [[ -n "${declared[$part]:-}" && -n "${bins[$part]:-}" && -n "${n_bins[$part]:-}" && -n "${ids[$part]:-}" ]] || { echo "missing part $part" >&2; exit 1; }
    bin_size=$(stat -Lc %s "${bins[$part]}")
    n_size=$(stat -Lc %s "${n_bins[$part]}")
    [[ "$bin_size" -eq "$n_size" && $((bin_size % 4)) -eq 0 ]] || { echo "binary family size mismatch for part $part" >&2; exit 1; }
    id_count=0
    while IFS=$'\t ' read -r fid iid extra; do
        [[ -n "$fid" && -n "$iid" && -z "${extra:-}" ]] || { echo "invalid GRM ID row in part $part" >&2; exit 1; }
        key="$fid"$'\t'"$iid"
        [[ -z "${seen_ids[$key]:-}" ]] || { echo "duplicate GRM ID: $key" >&2; exit 1; }
        seen_ids["$key"]=1
        ((id_count+=1))
    done < "${ids[$part]}"
    expected_elements=$(( (previous_ids + id_count) * (previous_ids + id_count + 1) / 2 - previous_ids * (previous_ids + 1) / 2 ))
    [[ $((bin_size / 4)) -eq "$expected_elements" ]] || { echo "dimension mismatch for part $part" >&2; exit 1; }
    cat "${bins[$part]}" >> "${prefix}.grm.bin"
    cat "${n_bins[$part]}" >> "${prefix}.grm.N.bin"
    cat "${ids[$part]}" >> "${prefix}.grm.id"
    previous_ids=$((previous_ids + id_count))
done

printf '"%s":\n    gctamergegrmparts: 1.0.0\n' "$process_name" > versions.yml
