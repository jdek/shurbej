{
  lib,
  stdenv,
  beamPackages,
  fetchHex,
  buildNpmPackage,
  nodejs,
  makeWrapper,
  simdjson,
  libsodium,
  pkg-config,
  coreutils,
  gawk,
  gnugrep,
  gnused,
  procps,
}: let
  pname = "shurbej";
  version = "0.1.0";

  # Hex deps — sha256 is the hash of the outer hex tarball.
  # Hashes pinned against rebar.lock; regenerate with:
  #   nix-prefetch-url https://repo.hex.pm/tarballs/<pkg>-<ver>.tar
  hexDeps = {
    cowboy = fetchHex {
      pkg = "cowboy";
      version = "2.12.0";
      sha256 = "07k5hbprnqvi2ym12fcaw5r2par8r6z0j9xa3jrcwwik31nvwyla";
    };
    cowlib = fetchHex {
      pkg = "cowlib";
      version = "2.13.0";
      sha256 = "1900723lif54319q2sr4qd3dm6byms1863ddn5j0l0zwqd6jiqg1";
    };
    ranch = fetchHex {
      pkg = "ranch";
      version = "1.8.0";
      sha256 = "1rfz5ld54pkd2w25jadyznia2vb7aw9bclck21fizargd39wzys9";
    };
    simdjsone = fetchHex {
      pkg = "simdjsone";
      version = "0.5.0";
      sha256 = "0mk87xndxiqm195xqqxq4mdvqqsyjrvcykiarblarxlmh2mdsjjx";
    };
  };

  web = buildNpmPackage {
    pname = "shurbej-web";
    inherit version;
    src = lib.cleanSource ../web;

    # Regenerate with: `prefetch-npm-deps web/package-lock.json`
    npmDepsHash = "sha256-HZror2sfv2ptUyYtmFUPLRQbqb20ZQokEk+H8ow9o9c=";

    dontNpmInstall = true;

    installPhase = ''
      runHook preInstall
      cp -r dist $out
      runHook postInstall
    '';
  };
in
  stdenv.mkDerivation (finalAttrs: {
    inherit pname version;
    src = lib.cleanSource ../.;

    nativeBuildInputs = [
      beamPackages.rebar3
      beamPackages.erlang
      nodejs
      makeWrapper
      pkg-config
    ];

    buildInputs = [simdjson libsodium];

    # rebar3 fetches into $HOME/.cache/rebar3; network is off in the sandbox.
    # `_checkouts/<name>` is rebar3's local-override mechanism: deps placed
    # there skip the hex registry check and compile straight from source.
    configurePhase = ''
      runHook preConfigure
      export HOME=$TMPDIR
      export REBAR_CACHE_DIR=$TMPDIR/rebar3-cache

      mkdir -p _checkouts
      ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: dep: ''
          cp -rL --no-preserve=mode ${dep} _checkouts/${name}
        '')
        hexDeps)}

      # Use the prebuilt web bundle instead of running vite inside this build
      mkdir -p web
      cp -r ${web} web/dist
      chmod -R u+w web/dist
      runHook postConfigure
    '';

    buildPhase = ''
      runHook preBuild
      rebar3 as prod release
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p $out/libexec/shurbej $out/bin
      cp -r _build/prod/rel/shurbej/. $out/libexec/shurbej/

      # Ship the built SPA inside the release so web_dist_dir can point at it
      cp -r web/dist $out/libexec/shurbej/web_dist

      # Thin launcher so users don't have to know the release path.
      makeWrapper $out/libexec/shurbej/bin/shurbej $out/bin/shurbej \
        --set-default RELX_REPLACE_OS_VARS true \
        --prefix PATH : ${lib.makeBinPath [coreutils gawk gnugrep gnused procps]}

      runHook postInstall
    '';

    meta = {
      description = "Self-hosted Zotero sync server with basic web UI";
      homepage = "https://github.com/jdek/shurbej";
      license = lib.licenses.wtfpl;
      platforms = lib.platforms.linux ++ lib.platforms.darwin;
      mainProgram = "shurbej";
    };
  })
