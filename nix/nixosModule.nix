{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.shurbej;
  inherit (lib) mkEnableOption mkIf mkOption optionalString types;

  listenTerm =
    if cfg.socketPath != null
    then ''{listen, {unix, "${cfg.socketPath}"}}''
    else ''{listen, {tcp, ${toString cfg.port}}}'';

  # Stacked on top of the release's sys.config via `-config` in ERL_FLAGS,
  # so later values win. `${SHURBEJ_COOKIE}` in vm.args is still substituted
  # from the environment via RELX_REPLACE_OS_VARS.
  #
  # The relx startup script cd's into ROOTDIR (the read-only nix store)
  # before exec'ing erlexec, so mnesia's default `Mnesia.<node>` directory
  # resolves there too. Override `mnesia.dir` so tables land in dataDir
  # regardless of cwd.
  overrideConfig = pkgs.writeText "shurbej-overrides.config" ''
    [
      {shurbej, [
        ${listenTerm},
        {file_storage_path, "${cfg.dataDir}/files"},
        {base_url, "${cfg.baseUrl}"},
        {web_dist_dir, "${cfg.package}/libexec/shurbej/web_dist"}
      ]},
      {mnesia, [
        {dir, "${cfg.dataDir}/mnesia"}
      ]}
    ].
  '';
in {
  options.services.shurbej = {
    enable = mkEnableOption "shurbej self-hosted Zotero sync server";

    package = mkOption {
      type = types.package;
      default = pkgs.shurbej;
      defaultText = lib.literalExpression "pkgs.shurbej";
      description = "The shurbej package to run.";
    };

    user = mkOption {
      type = types.str;
      default = "shurbej";
      description = "User account the service runs under.";
    };

    group = mkOption {
      type = types.str;
      default = "shurbej";
      description = "Group the service runs under.";
    };

    port = mkOption {
      type = types.port;
      default = 8080;
      description = ''
        TCP port shurbej's HTTP server listens on. Ignored when
        `socketPath` is set. Expected to be fronted by a reverse proxy;
        shurbej itself does not terminate TLS.
      '';
    };

    socketPath = mkOption {
      type = types.nullOr types.path;
      default = null;
      example = "/run/shurbej/http.sock";
      description = ''
        If non-null, shurbej listens on a Unix domain socket at this path
        instead of `port`. Place it under `/run/shurbej` (the unit's
        RuntimeDirectory) so systemd cleans it up on stop. The socket is
        chmod'd 0660 by shurbej on bind; the reverse proxy's user must
        therefore share `group` for the connect to succeed.

        When this is set and `services.nginx.enable` is also true, this
        module adds the nginx user to `group` automatically.
      '';
    };

    baseUrl = mkOption {
      type = types.str;
      example = "https://zotero.example.com";
      description = ''
        Public base URL where shurbej is reachable. Zotero clients use this
        when constructing absolute links in sync responses.
      '';
    };

    dataDir = mkOption {
      type = types.path;
      default = "/var/lib/shurbej";
      description = ''
        Directory for mnesia tables and uploaded files. The systemd unit
        runs with this as its working directory, so the default mnesia dir
        (`Mnesia.shurbej@<host>`) lands here as well.
      '';
    };

    cookieFile = mkOption {
      type = types.path;
      description = ''
        Path to a systemd EnvironmentFile containing the Erlang distribution
        cookie as a `SHURBEJ_COOKIE=<hex>` line. The cookie gates remote
        `eval` / admin operations on the node. Generate with:

            printf 'SHURBEJ_COOKIE=%s\n' "$(openssl rand -hex 32)" \
              | sudo install -m 0400 -o shurbej /dev/stdin /var/lib/shurbej/cookie
      '';
    };
  };

  config = mkIf cfg.enable {
    users.users = lib.mkMerge [
      (mkIf (cfg.user == "shurbej") {
        shurbej = {
          group = cfg.group;
          isSystemUser = true;
          home = cfg.dataDir;
        };
      })
      # Let nginx into the group so it can connect to the chmod 0660 socket.
      # No-op when nginx isn't enabled or when listening on TCP.
      (mkIf (cfg.socketPath != null && config.services.nginx.enable) {
        nginx.extraGroups = [cfg.group];
      })
    ];

    users.groups = mkIf (cfg.group == "shurbej") {
      shurbej = {};
    };

    systemd.services.shurbej = {
      description = "Shurbej self-hosted Zotero sync server";
      after = ["network.target"];
      wantedBy = ["multi-user.target"];

      environment = {
        RELX_REPLACE_OS_VARS = "true";
        # The release ships vm.args.src and sys.config in the read-only nix
        # store, but relx's startup script writes the env-substituted output
        # back next to the source by default. Redirect those writes into the
        # RuntimeDirectory below so boot can proceed.
        RELX_OUT_FILE_PATH = "/run/shurbej";
        ERL_FLAGS = "-config ${overrideConfig}";
        HOME = cfg.dataDir;
      };

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.group;
        WorkingDirectory = cfg.dataDir;
        # Lets systemd create dataDir and chown it to the service user on
        # first start. Defaults to /var/lib/<name>, matching dataDir's
        # default; if dataDir is overridden, set StateDirectory to a
        # matching path or remove this and pre-provision externally.
        StateDirectory = "shurbej";
        StateDirectoryMode = "0750";
        RuntimeDirectory = "shurbej";
        EnvironmentFile = cfg.cookieFile;
        ExecStart = "${cfg.package}/bin/shurbej foreground";
        Restart = "on-failure";
        RestartSec = 5;

        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictSUIDSGID = true;
        ReadWritePaths = [cfg.dataDir];
      };
    };
  };
}
