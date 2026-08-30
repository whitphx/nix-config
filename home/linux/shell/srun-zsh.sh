#!/bin/bash
# An interactive shell on a GPU node: a Slurm allocation whose task is
# apptainer-zsh, which is the only way into the Nix environment on the
# compute nodes (see apptainer-zsh.sh for why the chroot cannot go
# there).
#
#   srun-zsh                        one GPU on the configured partition
#   srun-zsh -c 8 --mem 64G         extra srun flags; they come after the
#                                   defaults, so they win
#   srun-zsh -- -c 'python x.py'    run a command instead of a shell
#
# $SRUN_ZSH_PARTITION and $SRUN_ZSH_GPUS override the configured
# defaults for one invocation.

partition="${SRUN_ZSH_PARTITION:-@partition@}"
gpus="${SRUN_ZSH_GPUS:-@gpus@}"
entry="$HOME/.local/bin/apptainer-zsh"

# Everything before `--` is for srun, everything after is for the shell
# the job starts.
srun_args=()
task_args=()
after_sep=0
for arg in "$@"; do
  if [ "$after_sep" = 0 ] && [ "$arg" = "--" ]; then
    after_sep=1
    continue
  fi
  if [ "$after_sep" = 1 ]; then
    task_args+=("$arg")
  else
    srun_args+=("$arg")
  fi
done

command -v srun >/dev/null \
  || { echo "srun-zsh: no srun on ${HOSTNAME:-this host}; run this from a submit node." >&2; exit 127; }
[ -x "$entry" ] \
  || { echo "srun-zsh: $entry is missing; activate the config on a host that shares this home." >&2; exit 127; }

# Only supply a default the caller did not already give, rather than
# leaning on srun to let a later flag win.
given() {
  local short=$1 long=$2 arg
  for arg in "${srun_args[@]}"; do
    case "$arg" in
      "$short" | "$short"[!-]* | "$long" | "$long"=*) return 0 ;;
    esac
  done
  return 1
}

args=()
[ -n "$partition" ] && ! given -p --partition && args+=(-p "$partition")
[ -n "$gpus" ] && ! given -G --gpus && args+=(-G "$gpus")
# --pty is for the shell case only; with a command to run it would just
# allocate a terminal nothing reads.
[ ${#task_args[@]} -eq 0 ] && args+=(--pty)

exec srun "${args[@]}" "${srun_args[@]}" "$entry" "${task_args[@]}"
