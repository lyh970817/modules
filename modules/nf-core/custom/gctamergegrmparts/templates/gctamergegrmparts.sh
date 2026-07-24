#!/usr/bin/env bash
cat \$(ls *.grm.bin | sort -V) > "${prefix}.grm.bin"
cat \$(ls *.grm.N.bin | sort -V) > "${prefix}.grm.N.bin"
cat \$(ls *.grm.id | sort -V) > "${prefix}.grm.id"

cat <<-END_VERSIONS > versions.yml
"${task.process}":
    coreutils: \$(cat --version | head -n1 | sed 's/^.*) //')
END_VERSIONS
