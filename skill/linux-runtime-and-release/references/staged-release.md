# Staging, activation and recovery

Record target, baseline and candidate file identities, dependency compatibility, available space, service/mount state and recovery entry. Keep source/build/staged/active boundaries visible. Temporary staging can be reviewed without boot writes.

Stop affected clients through supported interfaces and confirm ownership/drain before replacing hardware or drivers. Re-resolve mounts and media identity immediately before any authorized write. Do not force-unmount a busy filesystem or repair a live filesystem to silence a warning.

Copy candidate files under nonconflicting names and verify the intended set. Individual file renames do not make a multi-file boot update power-loss atomic; state the actual gap and recovery path. Preserve previous files and read back under the supported platform strategy. Reboot or physical power changes require the task's concrete authorization.

Keep running, next-boot and default profiles distinct. Restoring baseline boot files after a one-shot experiment need not change the currently running logic/application. Verify both transition directions, real runtime identities and service policy; a candidate boot alone does not verify rollback.

Separate normal stop/start, Linux reboot and physical cold power-on. Offline state-machine simulation does not prove a physical fault-recovery path. If DMA cannot be confirmed quiescent, retain its isolation/quarantine and use the declared recovery class instead of speculative unload/free/reset.

The regular-file verifier supports an explicit `format:1` and nonempty `files` mapping of portable relative paths to SHA-256. Only listed regular-file bytes are verified; symlink components below the resolved root are rejected. Lexical Windows-drive and colon-bearing paths are rejected for portability.
