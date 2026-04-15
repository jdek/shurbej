{
  inputs.flakelight.url = "github:nix-community/flakelight";
  outputs = { flakelight, ... }:
    flakelight ./. {
      systems = [ "aarch64-darwin" "x86_64-linux" ];
      devShell.packages = pkgs: with pkgs; [
        beamPackages.rebar3
        beamPackages.erlang
        erlang-language-platform
        libsodium
        pkg-config
        poppler-utils
        zig
        zvbi
        wrk
        # chrony
     ];
     formatter = pkgs: pkgs.alejandra;
  };
}
