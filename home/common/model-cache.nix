# Where model checkpoints are cached, which is a per-site fact: it wants
# a volume with room for tens of GB per checkpoint, and on a machine
# whose $HOME is shared across hosts, one that all of them mount. The
# path itself names infrastructure, so it belongs in a host's own config
# rather than here.
{ lib, ... }:
{
  options.myEnv.modelCacheDir = lib.mkOption {
    type = lib.types.str;
    default = "";
    example = "/data/<volume>/users/$USER/huggingface";
    description = ''
      Sets `HF_HOME`, for shells on hosts where the volume holding it is
      mounted; elsewhere the default `~/.cache/huggingface` stands. `$USER`
      is left for the shell to expand. Empty disables the override.
    '';
  };
}
