#!/usr/bin/env bash

set -euox pipefail

# Usage: `./pdg.sh <test crate dir> <test binary args...>`
# 
# Environment Variables:
# * `PROFILE` (default `release`):
#       a `cargo` profile as in `target/$PROFILE`
# * `BINARY` (default calculated by `get-binary-names-from-cargo-metadata.mjs`, require node):
#       the name of the binary produced by the test crate
# 
# Instrument and run a test crate and create its PDG.
# 
# 1. Compile the whole `c2rust` workspace, including `c2rust instrument`.
# 2. If the `c2rust-instrument` binary has changed,
#    re-instrument the test crate using `c2rust instrument`.
#    The produced metadata is saved to `metadata.bc`.
#    It always has to be `cargo clean`ed first,
#    for not quite known reasons, which may be:
#    * interactions between the default `cargo` run and the `cargo` invocation in `c2rust instrument`
#    * and/or incremental compilation
# 3. Redirect `c2rust instrument` output to `instrument.out.log` and `instrument.err.jsonl`.
#    These are in the test crate directory.
#    If there is an error, `instrument.err.jsonl` is pretty-printed.
# 4. Run the instrumented binary directly.
#    Note that `cargo run` can't be used because
#    that will recompile without instrumentation.
#    The `bincode`-encoded event log is written to `log.bc`.
# 5. Using the `metadata.bc` metadata and the `log.bc` event log,
#    run `c2rust-pdg` to generate the pdg.
#    The output is saved to `pdg.log` (relative to the test crate directory),
#    This output is just a debug representation of the PDG.
#    Except for the `=>`-containing lines, 
#    which are from the `latest_assignments` `HashMap`,
#    we want this output to remain stable.
#
# A couple of other notes:
# * `c2rust instrument` can only run the default `cargo` profile and settings right now.
#   See https://github.com/immunant/c2rust/issues/448 for why.
#   Thus, the instrumented binary is always in `dev`/`debug`` mode.
#   The other crates are compiled in `release` mode by default,
#   though that can be overridden by setting `PROFILE=debug` or another `cargo` profile.
#
# Requirements:
# * A recent node for some scripts.  `node@18.2.0` works.
main() {
    local script_path="${0}"
    local test_dir="${1}"
    local args=("${@:2}")

    local profile_dir_name="${PROFILE:-release}"
    local cwd="${PWD}"

    local script_dir="${cwd}/$(dirname "${script_path}")"

    local profile_dir="target/${profile_dir_name}"
    local profile="${profile_dir_name}"
    if [[ "${profile}" == "debug" ]]; then
        profile=dev
    fi
    local profile_args=(--profile "${profile}")

    cargo build "${profile_args[@]}" --features dynamic-instrumentation

    export RUST_BACKTRACE=1
    unset RUSTC_WRAPPER

    local c2rust="${cwd}/${profile_dir}/c2rust"
    local c2rust_instrument="${cwd}/${profile_dir}/c2rust-instrument"
    local runtime="${cwd}/analysis/runtime/"
    local metadata="${cwd}/${test_dir}/metadata.bc"

    (cd "${test_dir}"
        local binary_name
        if [[ "${BINARY:-}" != "" ]]; then
            binary_name="${BINARY}"
        else
            binary_name="$(command cargo metadata --format-version 1 \
                | "${script_dir}/get-binary-names-from-cargo-metadata.mjs" default)"
        fi
        local profile_dir="target/debug" # always dev/debug for now
        local binary_path="${profile_dir}/${binary_name}"
        
        if [[ "${c2rust_instrument}" -nt "${metadata}" ]]; then
            cargo clean --profile dev # always dev/debug for now

            if ! "${c2rust}" instrument \
                "${metadata}" "${runtime}" \
                -- "${profile_args[@]}"  \
            1> instrument.out.log \
            2> instrument.err.jsonl; then
                # delete so that we'll re-compile next time
                # instead of thinking it's already done
                rm -f "${metadata}"
                "${script_dir}/pretty-instrument-err.mjs" < instrument.err.jsonl
                return 1;
            fi
        fi
        
        export INSTRUMENT_BACKEND=log
        export INSTRUMENT_OUTPUT=log.bc
        export INSTRUMENT_OUTPUT_APPEND=false
        export METADATA_FILE="${metadata}"
        "${binary_path}" "${args[@]}"
    )
    (cd pdg
        export RUST_BACKTRACE=full # print sources w/ color-eyre
        export RUST_LOG=info
        cargo run \
            "${profile_args[@]}" \
            -- \
            --event-log "../${test_dir}/log.bc" \
            --metadata "${metadata}" \
            --print graphs \
            --print write-permissions \
            --print counts \
        > "../${test_dir}/pdg.log"
    )
}

main "${@}"
