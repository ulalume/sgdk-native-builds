# sgdk-native-builds

Self-contained **native SGDK distributions** per platform (linux x86_64 / arm64,
macOS arm64 / x86_64), built against the prebuilt gcc 13 toolchain. Each bundle
contains native SGDK tools (xgmtool / bintos / convsym / sjasm) + `mac68k` +
`libmd.a` / `libmd_debug.a` + generated docs, usable with `make -f makefile.gen`
once a gcc toolchain is on PATH.

## Dependencies (downloaded at build time, not rebuilt)

| Component | Source | Release |
|---|---|---|
| gcc 13 toolchain | [ulalume/m68k-toolchain-builds](https://github.com/ulalume/m68k-toolchain-builds) | `gcc13.2.0-1` |
| mac68k | [ulalume/maccer](https://github.com/ulalume/maccer) | `v0.26-1` |
| SGDK source | [Stephane-D/SGDK](https://github.com/Stephane-D/SGDK) | requested ref |

Build logic mirrors `sgdk-setup.sh` (build tools + `makelib.gen`).

## Workflows

| Workflow | Role | Trigger |
|---|---|---|
| `build.yml` | Build one SGDK ref → release (4 platforms) | `workflow_dispatch` (ref + tag) / `workflow_call` |
| `sync.yml` (planned) | Build all tags since v2.00 + master | schedule / dispatch |

**Coverage:** tags since v2.00 + master are pre-built; any other commit is built
on demand via `build.yml`.

## Config

gcc 13 only. Update `TOOLCHAIN_TAG` / `MACCER_TAG` in `build.yml` when those repos
cut new releases.

## Licenses

- **This repository** (workflows): GPL-3.0-or-later (see `LICENSE`).
- Produced bundles contain third-party components under their own licenses:
  SGDK (Stephane-D/SGDK license), `convsym` (MIT, vladikcomper), `sjasm` (Konamiman),
  `mac68k` (GPL-2.0-or-later).
