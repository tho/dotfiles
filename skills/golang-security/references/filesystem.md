# Filesystem confinement

Protect the intended storage root and the confidentiality and integrity of its contents. Lexical path validation and filesystem confinement address different threats.

- On Go 1.24+, use `os.OpenRoot` and supported `os.Root` operations for untrusted relative paths. Check the project's Go version for individual methods. Root operations constrain traversal and escaping symlinks; they are not a complete sandbox against hostile mounts, device files, or special filesystems.
- On older Go versions, `filepath.IsLocal` and separator-aware `filepath.Rel` checks can reject lexical escapes. They do not prevent symlink traversal or races between checking and opening. Where an attacker can mutate the directory tree, use a suitable traversal-resistant facility or change that trust assumption.
- `filepath.Clean`, joining to a base directory, and a string prefix comparison do not establish confinement. Similar prefixes, absolute paths, platform separators, symlinks, and concurrent replacement matter.
- Use unpredictable temporary files or private temporary directories.
- Create private keys and secrets with restrictive permissions, typically `0600`; choose directory access from the actual sharing policy. Creation permissions do not tighten an existing file. Decide explicitly whether to reject existing targets or safely manage their permissions and ownership, including symlink behavior.

## Archive and upload boundaries

Confine each extracted entry, reject unsupported special files, and define symlink, duplicate-entry, and overwrite policies. An archive's declared sizes are untrusted. Count actual decompressed bytes and bound both individual entries and the total, plus entry count and processing time.

Detect exceeding the limit as an error, not successful truncated output. A bounded copy can read at most the remaining budget plus one detection byte; distinguish exact-limit success from overflow without writing the extra byte. Remove or quarantine incomplete output according to the storage contract. Avoid retaining one open file per entry for the lifetime of the whole archive.

Verify traversal, escaping symlinks, overwrite behavior, exact and over-limit decompression, and ordinary nested files. Include platform-specific path cases supported by the application.
