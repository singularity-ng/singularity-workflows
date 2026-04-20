{pkgs ? import <nixpkgs> {}}:
pkgs.mkShell {
  buildInputs = [
    pkgs.beam.packages.erlang_28.elixir_1_19
    pkgs.beam.packages.erlang_28.erlang
  ];
}
