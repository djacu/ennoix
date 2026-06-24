{ lib }:
{
  name,
  builtIn ? false,
  # use-package keyword defaults — passthrough: the values are emitted as
  # literal elisp verbatim (lists join into `:kw (…)`, lines into `:kw …`,
  # bools into `:kw t`). Curated values are the option defaults; a user
  # override REPLACES (mkOptionDefault priority). `extraConfig` sets `config`.
  init ? "",
  extraConfig ? "",
  after ? [ ],
  bind ? [ ],
  commands ? [ ],
  custom ? [ ],
  hook ? [ ],
  mode ? [ ],
  defer ? false,
  demand ? false,
}:
_:
let
  inherit (lib) mkOption mkEnableOption types;
in
{
  options.plugins.${name} = {
    enable = mkEnableOption name;
    package = mkOption {
      type = types.nullOr types.str;
      default = if builtIn then null else name;
      description = "Package name in the emacs scope; `null` for a built-in.";
    };
    after = mkOption {
      type = types.listOf types.str;
      default = after;
    }; # :after
    bind = mkOption {
      type = types.listOf types.str;
      default = bind;
    }; # :bind  e.g. [ ''("C-x g" . magit-status)'' ]
    commands = mkOption {
      type = types.listOf types.str;
      default = commands;
    }; # :commands
    custom = mkOption {
      type = types.listOf types.str;
      default = custom;
    }; # :custom e.g. [ "(corfu-auto t)" ]
    hook = mkOption {
      type = types.listOf types.str;
      default = hook;
    }; # :hook  e.g. [ "(prog-mode . foo-mode)" ]
    mode = mkOption {
      type = types.listOf types.str;
      default = mode;
    }; # :mode
    defer = mkOption {
      type = types.bool;
      default = defer;
    }; # :defer t
    demand = mkOption {
      type = types.bool;
      default = demand;
    }; # :demand t
    init = mkOption {
      type = types.lines;
      default = init;
    }; # :init
    config = mkOption {
      type = types.lines;
      default = extraConfig;
    }; # :config
  };
}
