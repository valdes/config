{ lib, rustPlatform, makeWrapper, jdt-language-server }:

rustPlatform.buildRustPackage {
  pname = "java-lsp";
  version = "0.1.0";
  src = lib.cleanSourceWith {
    src = ./.;
    filter = path: type:
      builtins.baseNameOf path != "target" && lib.cleanSourceFilter path type;
  };
  cargoLock.lockFile = ./Cargo.lock;
  nativeBuildInputs = [ makeWrapper ];
  postInstall = ''
    install -Dm644 README.md "$out/share/doc/java-lsp/README.md"
    wrapProgram "$out/bin/java-lsp" \
      --set-default JAVA_LSP_JDTLS ${jdt-language-server}/bin/jdtls
  '';
  meta = {
    description = "Persistent JDT LS CLI for coding agents";
    mainProgram = "java-lsp";
    platforms = lib.platforms.linux;
  };
}
