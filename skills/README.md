# Tracked Codex Skills

This directory is the version-controlled source of the operational skills
used for the foxii deployment.

The local Codex skill directories under `~/.codex/skills/` should be
symlinks to the directories here. Commit changes in this repository instead
of editing an untracked copy.

```bash
ln -s /Users/mac038/Documents/GitHub/infra/skills/aliyun-ecs-ingress \
  /Users/mac038/.codex/skills/aliyun-ecs-ingress
ln -s /Users/mac038/Documents/GitHub/infra/skills/forvision-server \
  /Users/mac038/.codex/skills/forvision-server
```
