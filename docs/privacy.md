# Privacy policy: homelab-backup

`homelab-backup` is a Google Cloud OAuth client used by a single person, the
owner of this repository, to store backups of their own home server in their
own Google Drive. It is not offered to anyone else.

## Data accessed

- The app requests only the `drive.file` scope. It can see and manage only
  the files it creates itself (the `homelab-restic/` folder). It cannot read
  any other file in the Drive.
- No profile, contact, email or other Google account data is requested.

## How the data is used

- Files are written by [rclone](https://rclone.org) running on the owner's
  server (CT 301 `ops-backup`, see [backup.md](backup.md)).
- Everything is encrypted by restic on the server before upload. Google
  stores only ciphertext. The encryption key never leaves the owner's
  infrastructure.
- The data is not shared with, sold to or processed by any third party.

## Retention and deletion

Backups are kept as described in [backup.md](backup.md) (7 daily, 4 weekly,
12 monthly) and pruned automatically. Revoking the app at
<https://myaccount.google.com/permissions> stops all access immediately.
Deleting the `homelab-restic/` folder removes all stored data.

## Contact

Open an issue in this repository.
