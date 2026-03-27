# laptop_configuration

A simple bootstrap.sh script & Ansible playbook to bootstrap a fresh installed Linux laptop.

## Installation

Download `bootstrap.sh`, review it, run it:

```bash
curl -fsSL -H 'Cache-Control: no-cache' -o bootstrap.sh https://raw.githubusercontent.com/ceso/laptop_configuration/refs/heads/master/bootstrap.sh
less bootstrap.sh
bash bootstrap.sh
```

The script will update the system, install system dependencies, Linuxbrew, Ansible & and clone this repo.
If extra configurations roles and/or variables are needed beyond the ones in laptop.yml, a directory must be created under `host_vars/` with extras.

## Bootstrap flags

| Flag | Description |
|------|-------------|
| `--repo-dir <path>` | Directory to clone the repo into (default: `~/Projects/laptop_configuration`) |
| `--laptop <name>` | Target laptop name (default: `tuxedo`) |
| `-h, --help` | Show help message |

## Laptop configuration example (extras)

Create a directory under `host_vars/` matching your laptop name (e.g., `host_vars/example-laptop/`). Include:

### `host_vars/example-laptop/extra_packages.yml`
```yaml
extra_packages:
  - example-package-1
  - example-package-2
  - example-cli-tool
```

### `host_vars/example-laptop/extra_roles.yml`
```yaml
extra_roles:
  - role: example.custom-role
    tags:
      - custom
  - role: example.another-role
    become: true
    tags:
      - admin
```

### `host_vars/example-laptop/requirements.yml`
```yaml
---                                        1
collections:
  - name: example.collection
    version: ">=1.0.0"

roles:
  - name: example.galaxy-role
    src: https://github.com/example/ansible-example-role.git
```

## Requirements

- Debian, Fedora/RHEL
- `sudo` access
- Internet connectivity

## Running the playbook again

After the initial bootstrap, re-run directly (for example):

```bash
cd ~/Projects/laptop_configuration
ansible-galaxy collection install -r requirements.yml --force
ansible-galaxy role install -r requirements.yml --force
ansible-playbook laptop.yml --ask-become-pass
ansible-playbook laptop.yml --tasks=dotfiles
```

## Testing

TODO
