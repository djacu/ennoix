# The shared use-package entry type (adapted from rycee's usePackageType).
# NOTE: this submodule declares an OPTION named `config`; the module arg
# `config` below is the submodule's own config, so the option is read as
# `config.config`. Do not "fix" this — it mirrors rycee and use-package.
# (Entries can only SET a `config` key in shorthand because the namespace
# declares the submodule with shorthandOnlyDefinesConfig = true.)
{
  name,
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    concatStringsSep
    filterAttrs
    mapAttrsToList
    mkEnableOption
    mkOption
    mkPackageOption
    optional
    types
    ;

  quote = s: ''"${lib.strings.escape [ "\"" "\\" ] s}"'';

  # :custom value serialization: bool -> t/nil, int -> number,
  # string -> LITERAL elisp emitted verbatim (typed coercion stops here).
  toElisp =
    v:
    if builtins.isBool v then
      (if v then "t" else "nil")
    else if builtins.isInt v then
      toString v
    else
      v;

  listKw = kw: xs: optional (xs != [ ]) "  :${kw} (${concatStringsSep " " xs})";
  pairsKw =
    kw: f: attrs:
    optional (attrs != { }) "  :${kw} (${concatStringsSep " " (mapAttrsToList f attrs)})";
  linesKw = kw: s: optional (s != "") "  :${kw} ${s}";
  boolKw = kw: b: optional b "  :${kw} t";
  deferKw = d: if builtins.isBool d then optional d "  :defer t" else [ "  :defer ${toString d}" ];
  bindPair = key: cmd: "(${quote key} . ${cmd})";
  # one ":bind (:map <name> ...)" line per local keymap (rycee's emission;
  # use-package merges repeated :bind occurrences)
  bindLocalKw =
    maps:
    mapAttrsToList (
      mapName: pairs: "  :bind (:map ${mapName} ${concatStringsSep " " (mapAttrsToList bindPair pairs)})"
    ) (filterAttrs (_: pairs: pairs != { }) maps);
in
{
  options = {
    enable = mkEnableOption "the ${name} use-package entry";
    package = mkPackageOption pkgs.emacsPackages name {
      nullable = true;
      pkgsText = "pkgs.emacsPackages";
    };
    runtimePackages = mkOption {
      type = types.listOf types.package;
      default = [ ];
      description = "Non-elisp binaries placed on the built emacs's PATH.";
    };
    extraPackages = mkOption {
      type = types.listOf types.package;
      default = [ ];
      description = "Extra elisp packages installed without a use-package form of their own.";
    };
    after = mkOption {
      type = types.listOf types.str;
      default = [ ];
    }; # :after
    bind = mkOption {
      type = types.attrsOf types.str;
      default = { };
      description = ":bind — key = keybinding string, value = command.";
    };
    bind' = mkOption {
      type = types.attrsOf types.str;
      default = { };
      description = ":bind* — like bind, but overrides minor-mode maps.";
    };
    bindKeyMap = mkOption {
      type = types.attrsOf types.str;
      default = { };
      description = ":bind-keymap — key = keybinding string, value = keymap.";
    };
    bindLocal = mkOption {
      type = types.attrsOf (types.attrsOf types.str);
      default = { };
      description = "Local keymap binds: keymap name -> { key = command; }.";
    };
    commands = mkOption {
      type = types.listOf types.str;
      default = [ ];
    }; # :commands (rycee's `command`, deliberately renamed)
    custom = mkOption {
      type = types.attrsOf (
        types.oneOf [
          types.bool
          types.int
          types.str
        ]
      );
      default = { };
    }; # :custom
    defines = mkOption {
      type = types.listOf types.str;
      default = [ ];
    }; # :defines (byte-compiler declarations)
    functions = mkOption {
      type = types.listOf types.str;
      default = [ ];
    }; # :functions (byte-compiler declarations)
    hook = mkOption {
      type = types.listOf types.str;
      default = [ ];
    }; # :hook — literal elisp pairs
    interpreter = mkOption {
      type = types.listOf types.str;
      default = [ ];
    }; # :interpreter — literal elisp pairs
    mode = mkOption {
      type = types.listOf types.str;
      default = [ ];
    }; # :mode — literal elisp pairs
    defer = mkOption {
      type = types.either types.bool types.ints.positive;
      default = false;
    }; # :defer t / :defer N
    demand = mkOption {
      type = types.bool;
      default = false;
    }; # :demand t
    init = mkOption {
      type = types.lines;
      default = "";
    }; # :init
    config = mkOption {
      type = types.lines;
      default = "";
    }; # :config
    assembly = mkOption {
      type = types.lines;
      readOnly = true;
      internal = true;
      description = "The complete generated use-package form for this entry.";
    };
  };

  config.assembly = concatStringsSep "\n" (
    [ "(use-package ${name}" ]
    ++ boolKw "demand" config.demand
    ++ deferKw config.defer
    ++ listKw "after" config.after
    ++ listKw "commands" config.commands
    ++ listKw "defines" config.defines
    ++ listKw "functions" config.functions
    ++ listKw "mode" config.mode
    ++ listKw "interpreter" config.interpreter
    ++ listKw "hook" config.hook
    ++ pairsKw "bind" bindPair config.bind
    ++ pairsKw "bind*" bindPair config.bind'
    ++ pairsKw "bind-keymap" bindPair config.bindKeyMap
    ++ bindLocalKw config.bindLocal
    # NOTE: :custom attribute NAMES are spliced unescaped (rycee parity);
    # exotic quoted-attr names are the catalog author's responsibility.
    ++ pairsKw "custom" (var: v: "(${var} ${toElisp v})") config.custom
    ++ linesKw "init" config.init
    ++ linesKw "config" config.config
    ++ [ "  )" ]
  );
}
