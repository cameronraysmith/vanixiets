# claude-sandbox

## Revoking the Linear credentials

The cloud environment decrypts `secrets/home-manager/users/claude-sandbox/secrets.yaml` with the age key in its `SOPS_AGE_KEY` variable, the recipient `claude-sandbox-user` in `.sops.yaml`.
To revoke that access, on stibnite with the admin key:

1. Remove the recipient: delete `*claude-sandbox-user` from the `secrets/home-manager/users/claude-sandbox/.*\.yaml$` rule in `.sops.yaml`.
2. Re-encrypt that one file: `sops updatekeys secrets/home-manager/users/claude-sandbox/secrets.yaml`.
3. Rotate both Linear keys in Linear, `linear-api-key-personal` and `linear-api-key-work`, which are the ubuntu profile's agent Linear keys, shared with claude-sandbox; the old file in git history still opens with the removed key.
4. Clear the `SOPS_AGE_KEY` variable in the claude.ai cloud environment's settings.
