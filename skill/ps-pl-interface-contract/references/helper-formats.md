# Separate formats, no implicit conversion

## static-regions-v1

`scripts/check_static_contract.py CONTRACT [--header HEADER] [--baseline PREVIOUS] [--report NEW_JSON]` uses a static-region format: integer `schema_version:1`, `address_bits` 32/64, power-of-two `cache_line_bytes`, flat disjoint leaf `regions`, optional selected numeric `symbols`.

Regions specify name/kind/base/size/alignment and optional base/size C symbols; MMIO registers specify name/offset/width_bytes/access and optional C symbol. The header adapter supports direct object-like integer literals, parentheses and U/L suffixes only, not C preprocessing/expressions. It checks region/register bounds, start alignment, overlap and selected literals. The baseline compares normalized defined sections; descriptive/unknown extensions are outside that comparison. Exit 0/1/2 means matching checks / failure or drift for review / CLI-report error. `--report` refuses overwrite.

`assets/example-qr-v1-contract.json` is an adapter example with explicit addresses; derive a new target's configuration from its actual design. Its descriptor page reservation is not the descriptor's C sizeof.

## abi-description-v1

`scripts/compare_abi_descriptions.py --before BEFORE --after AFTER` uses a strict `format:1` description. Required keys: target, abi_version, mmio, structures, ioctls, identity_fields, completion. Optional provenance is excluded from comparison; other unknown keys and duplicate JSON keys are rejected.

MMIO has base/size/byte_order and nonoverlapping registers with name/offset/width/access/reset/semantics. Width is in bits. Structures have size/alignment/fields, and fields explicitly cover every byte, including padding. Ioctls have name/number/direction/argument referencing a structure or null for no argument. Identity order remains significant. All observed facts must be supplied, not guessed. Exit 0/1/2 means equal normalized descriptions / different valid descriptions requiring review / malformed or unsupported input.

The first format does not capture the second format's full structures, semantics or ioctls; the second is not a substitute for checking listed C macros/reservations. Neither automatically extracts interfaces or proves behavior. Use matching adapters, target compile checks and runtime evidence for the remaining boundary.
