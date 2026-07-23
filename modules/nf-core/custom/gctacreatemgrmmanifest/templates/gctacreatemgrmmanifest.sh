#!/usr/bin/env bash

set -euo pipefail

readonly ADAPTER_VERSION='1.0.0'
readonly OUTPUT_MANIFEST='${prefix}.mgrm'

grm_order=( $order_args )
grm_files=( $file_args )

fail() {
    echo "CUSTOM_GCTACREATEMGRMMANIFEST: \$*" >&2
    exit 1
}

(( \${#grm_order[@]} > 0 )) || fail 'grm_order must contain at least one GRM root.'
(( \${#grm_files[@]} > 0 )) || fail 'grm_files must contain complete GRM files.'

declare -A requested_roots=()
for root in "\${grm_order[@]}"; do
    [[ -n "\$root" ]] || fail 'grm_order contains an empty root.'
    [[ "\$root" != */* ]] || fail "GRM root '\$root' must be a staged basename, not a path."
    [[ "\$root" != *[[:space:]]* ]] || fail "GRM root '\$root' must not contain whitespace."
    [[ "\$root" != *.grm ]] || fail "GRM root '\$root' must omit the .grm suffix."
    [[ -z "\${requested_roots[\$root]+present}" ]] || fail "Duplicate GRM root in grm_order: '\$root'."
    requested_roots["\$root"]=1
done

declare -A discovered_roots=()
declare -A sidecars=()
for filename in "\${grm_files[@]}"; do
    [[ "\$filename" != */* ]] || fail "GRM file '\$filename' must be staged in the task directory."

    case "\$filename" in
        *.grm.N.bin)
            root="\${filename%.grm.N.bin}"
            suffix='grm.N.bin'
            ;;
        *.grm.bin)
            root="\${filename%.grm.bin}"
            suffix='grm.bin'
            ;;
        *.grm.id)
            root="\${filename%.grm.id}"
            suffix='grm.id'
            ;;
        *)
            fail "Unexpected GRM file '\$filename'; expected .grm.id, .grm.bin or .grm.N.bin."
            ;;
    esac

    [[ -n "\$root" ]] || fail "GRM file '\$filename' has an empty root."
    key="\$root|\$suffix"
    [[ -z "\${sidecars[\$key]+present}" ]] || fail "Duplicate GRM sidecar for root '\$root': '\$suffix'."
    sidecars["\$key"]=1
    discovered_roots["\$root"]=1
done

for root in "\${!discovered_roots[@]}"; do
    for suffix in grm.id grm.bin grm.N.bin; do
        [[ -n "\${sidecars[\$root|\$suffix]+present}" ]] || fail "Incomplete GRM root '\$root': missing '\$root.\$suffix'."
    done
    [[ -n "\${requested_roots[\$root]+present}" ]] || fail "GRM root '\$root' is present in grm_files but absent from grm_order."
done

for root in "\${grm_order[@]}"; do
    [[ -n "\${discovered_roots[\$root]+present}" ]] || fail "GRM root '\$root' is requested but absent from grm_files."
done

(( \${#requested_roots[@]} == \${#discovered_roots[@]} )) || fail 'grm_order and grm_files do not have a one-to-one root match.'

printf '%s\n' "\${grm_order[@]}" > "\$OUTPUT_MANIFEST"

cat > versions.yml <<END_VERSIONS
"$task.process":
    custom_gctacreatemgrmmanifest: \$ADAPTER_VERSION
END_VERSIONS
