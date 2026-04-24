{
  inputs.flakelight.url = "github:nix-community/flakelight";
  outputs = { flakelight, ... }:
    flakelight ./. {
      systems = [ "aarch64-darwin" "aarch64-linux" "x86_64-linux" ];

      devShell.packages = pkgs: with pkgs; [
        beamPackages.rebar3
        beamPackages.erlang
        erlang-language-platform
        libsodium
        simdjson
        pkg-config
      ];

      formatter = pkgs: pkgs.alejandra;
    };
}
