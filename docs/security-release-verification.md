# Verify CLEAR Release Artifacts

Do not execute the installer unless signature verification and checksum verification both pass.

## Required files

- `clear-installer-vX.Y.Z.sh`
- `clear-installer-vX.Y.Z.sha256`
- `clear-installer-vX.Y.Z.sha256.asc`

## Trust bootstrap

Canonical public key file:

- `docs/keys/clear-release-signing-public.asc`
- `docs/keys/clear-release-signing-fingerprint.txt`

Release signing key fingerprint:

- `35CD F523 D2E6 E479 53FC A25F A404 671B FB78 0D6E`

Before trusting the key, confirm this fingerprint out-of-band (README + release notes).
Then import the key:

```bash
gpg --import docs/keys/clear-release-signing-public.asc
gpg --fingerprint "CLEAR Release <james_clear@ketrenos.com>"
```

Only continue if the displayed fingerprint exactly matches the value above.

## Manual verification commands

```bash
gpg --verify clear-installer-vX.Y.Z.sha256.asc clear-installer-vX.Y.Z.sha256
sha256sum -c clear-installer-vX.Y.Z.sha256
bash clear-installer-vX.Y.Z.sh --target /path/to/repo
```

Optional extraction-only mode:

```bash
bash clear-installer-vX.Y.Z.sh --extract /path/to/extracted/payload
```

## Scripted local verification

```bash
./scripts/verify-release-artifacts.sh --version X.Y.Z --dir ./dist/release/vX.Y.Z
```

## Failure messages

- Signature verification failed:
  `Signature verification failed. Abort. Re-download artifacts and confirm the trusted signing key fingerprint.`
- Checksum verification failed:
  `Checksum verification failed. Abort. Artifact may be corrupted or tampered.`
- Missing tools:
  `Required verification tools not found. Install gpg and sha256sum before running installer.`
- Key trust mismatch:
  `Signing key is untrusted or fingerprint mismatch. Abort until trust is established out-of-band.`
