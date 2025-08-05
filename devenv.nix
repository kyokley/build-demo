{ pkgs, lib, config, inputs, ... }:

{
  # https://devenv.sh/basics/
  env.GREET = "build-demo";

  # https://devenv.sh/packages/
  packages = [pkgs.fortune];

  # https://devenv.sh/languages/
  languages.python = {
    enable = true;
    version = "3.13";
    uv.enable = true;
  };

  # https://devenv.sh/processes/
  # processes.cargo-watch.exec = "cargo-watch";

  # https://devenv.sh/services/
  # services.postgres.enable = true;

  # https://devenv.sh/scripts/
  scripts = {
    hello.exec = ''
      echo Welcome to $GREET
    '';
    docker-build.exec = ''
      set -x
      docker build -t kyokley/build-demo .
    '';
    docker-run.exec = ''
      set -x
      docker run --rm -it --net=host kyokley/build-demo uv run python main.py
    '';
    docker-build-nix.exec = ''
      set -x
      docker build -t kyokley/build-demo-nix -f Dockerfile-nix .
    '';
    docker-run-nix.exec = ''
      set -x
      docker run --rm -it --net=host kyokley/build-demo-nix
    '';
    docker-build-nix2.exec = ''
      set -x
      nix build '.#docker-image'
      docker load < result
    '';
    docker-run-nix2.exec = ''
      set -x
      docker run --rm -it --net=host kyokley/build-demo-nix2
    '';
  };

  enterShell = ''
    hello
  '';

  # https://devenv.sh/tasks/
  # tasks = {
  #   "myproj:setup".exec = "mytool build";
  #   "devenv:enterShell".after = [ "myproj:setup" ];
  # };

  # https://devenv.sh/tests/
  enterTest = ''
    echo "Running tests"
  '';

  # https://devenv.sh/git-hooks/
  git-hooks.hooks = {
    ruff.enable = true;
    ruff-format.enable = true;
    mypy.enable = false;
    isort = {
      enable = true;
      settings.profile = "black";
    };
  };

  # See full reference at https://devenv.sh/reference/options/
}
