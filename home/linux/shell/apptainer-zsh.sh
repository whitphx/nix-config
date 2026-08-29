#!/bin/bash
# Entry point for a shell, or any command, inside a Slurm job.
#
# The chroot-zsh path cannot work there. The compute nodes run Ubuntu
# 24.04 with kernel.apparmor_restrict_unprivileged_userns=1, so an
# unprivileged process may create a user namespace but is then denied
# both the uid_map write and every mount inside it; nix-user-chroot dies
# with EACCES before it can pivot. Apptainer is installed on those nodes
# and is permitted to set up the same mounts, so the store is bound in
# through it instead.
#
# Meant to be the task of a job, which leaves every srun flag yours:
#   srun -p <partition> -G 1 --pty ~/.local/bin/apptainer-zsh
#   srun -p <partition> -G 1 ~/.local/bin/apptainer-zsh -c 'python train.py'
#
# $NIX_APPTAINER_IMAGE overrides the image. The default pulls Ubuntu from
# Docker Hub on first use. If the site blocks that, or apptainer will not
# create the /nix bind point inside it, build the image once from
# nix-config's home/linux/apptainer/nix-base.def, which carries the
# mount point, and point the variable at the result.

nix_dir="@nixDir@"
image="${NIX_APPTAINER_IMAGE:-docker://ubuntu:24.04}"
args=("$@")

fallback() {
  local shell=/bin/bash
  [ -x "$shell" ] || shell=/bin/sh

  if [ -t 2 ]; then
    {
      echo "apptainer-zsh: cannot bind the Nix store into this job, so this is a plain $shell."
      echo "  store:  $nix_dir"
      echo "  reason: $1"
      [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/          /'
      echo "  effect: nothing installed through Nix is on PATH here."
    } >&2
  else
    echo "apptainer-zsh: $1; running $shell without the Nix environment (store: $nix_dir)." >&2
  fi

  export NIX_APPTAINER_FALLBACK=1
  exec "$shell" -l "${args[@]}"
}

apptainer_bin=$(command -v apptainer || command -v singularity)
[ -n "$apptainer_bin" ] \
  || fallback "neither apptainer nor singularity is installed on ${HOSTNAME:-this node}"

# The store has to be on a volume this node mounts. Checking it here
# turns "the container starts and nothing is on PATH" into one line that
# names the volume.
[ -d "$nix_dir/store" ] \
  || fallback "no store there from ${HOSTNAME:-this node}, which probably does not mount that volume"

ap_args=(exec --bind "$nix_dir:/nix")
# Apptainer binds $HOME on its own; /data carries the model cache and has
# to be asked for.
[ -d /data ] && ap_args+=(--bind /data)
# --nv is an error on a node with no NVIDIA devices, so ask for the GPU
# stack only where there is one.
[ -e /dev/nvidiactl ] && ap_args+=(--nv)

exec "$apptainer_bin" "${ap_args[@]}" "$image" bash -lc 'exec zsh -l "$@"' bash "${args[@]}"
