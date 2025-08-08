---
title: Nix Build
slides:
    separator_vertical: ^\s*-v-\s*$
---

# :building_construction: Deterministic Builds :ship:

---

## :whale: Docker :whale:
Is Docker a good platform for creating reproducible builds? <!-- .element: class="fragment" -->

Notes:

Show of hands, who thinks Docker is a good platform for creating reproducible builds?

---

According to [Docker](https://www.docker.com/why-docker/)
> Docker introduced what would become the industry standard for containers. Containers are a standardized unit of software that allows developers to isolate their app from its environment, solving the “it works on my machine” headache.

---

:robot: According to ChatGPT :robot:
> Docker provides a solid foundation for reproducible builds, especially compared to traditional “run this bash script on a VM” setups. However, true reproducibility requires discipline—Docker makes it possible, but you have to make it happen.

---

#### :cat: Enter Fortune Cat :cat:
main.py
```python
import os
from subprocess import PIPE, run
from textwrap import wrap
from urllib.parse import quote

import httpx
import uvicorn
from fastapi import FastAPI, Response

FORTUNE_EXEC = os.environ.get("FORTUNE_EXEC") or "/app/bin/fortune"
app = FastAPI()


@app.get("/cat")
def cat():
    fortune = get_fortune()
    url = f"https://cataas.com/cat/cute/says/{fortune}"
    resp = httpx.get(
        url,
        params={
            "html": "true",
            "fontSize": "22",
        },
    )
    print(resp)
    return Response(content=resp.content)


def get_fortune():
    fortune = (
        run([f"{FORTUNE_EXEC}", "-s"], stdout=PIPE, check=True).stdout.decode().strip()
    )
    fortune = wrap(fortune)
    print(fortune)
    return quote("\n".join(fortune))


if __name__ == "__main__":
    uvicorn.run("main:app", host="127.0.0.1", port=8000, reload=True, workers=1)
```

Notes:

Fortune Cat is a python3.13 fastapi app that calls Cat-aaS and passes a message from the fortune CLI app

---

Let's build a container

---

Dockerfile
```dockerfile
FROM python:3.13-slim AS base

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV PYTHONPATH=.
ENV UV_FROZEN=true
ENV UV_PROJECT_ENVIRONMENT=/venv
ENV UV_CACHE_DIR=/uv_cache
ENV UV_PROJECT_DIR=${UV_PROJECT_ENVIRONMENT}
ENV VIRTUAL_ENV=${UV_PROJECT_ENVIRONMENT}
ENV PATH="$VIRTUAL_ENV/bin:$PATH"
ENV FORTUNE_EXEC=/usr/games/fortune

FROM base AS builder

RUN pip install --upgrade --no-cache-dir pip uv && \
        uv venv --seed ${VIRTUAL_ENV}

COPY uv.lock pyproject.toml ${UV_PROJECT_DIR}/

RUN uv sync --no-dev --project ${VIRTUAL_ENV}

FROM base AS final

RUN apt-get update && \
        apt-get install -y --no-install-recommends fortune fortunes && \
        pip install --upgrade --no-cache-dir pip uv

COPY --from=builder ${VIRTUAL_ENV} ${VIRTUAL_ENV}
COPY . ${UV_PROJECT_DIR}

WORKDIR ${UV_PROJECT_DIR}

CMD ["uv", "run", "python", "main.py"]
```
Notes:

What parts of this risk reproducibility?

-v-

:thinking: Potential Issues :thinking:
```dockerfile [1|25-27]
FROM python:3.13-slim AS base

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV PYTHONPATH=.
ENV UV_FROZEN=true
ENV UV_PROJECT_ENVIRONMENT=/venv
ENV UV_CACHE_DIR=/uv_cache
ENV UV_PROJECT_DIR=${UV_PROJECT_ENVIRONMENT}
ENV VIRTUAL_ENV=${UV_PROJECT_ENVIRONMENT}
ENV PATH="$VIRTUAL_ENV/bin:$PATH"
ENV FORTUNE_EXEC=/usr/games/fortune

FROM base AS builder

RUN pip install --upgrade --no-cache-dir pip uv && \
        uv venv --seed ${VIRTUAL_ENV}

COPY uv.lock pyproject.toml ${UV_PROJECT_DIR}/

RUN uv sync --no-dev --project ${VIRTUAL_ENV}

FROM base AS final

RUN apt-get update && \
        apt-get install -y --no-install-recommends fortune fortunes && \
        pip install --upgrade --no-cache-dir pip uv

COPY --from=builder ${VIRTUAL_ENV} ${VIRTUAL_ENV}
COPY . ${UV_PROJECT_DIR}

WORKDIR ${UV_PROJECT_DIR}
```

Notes:
* The image defined in the first line isn't pinned

* Commands like "apt update", "apk update", etc. could change package versions across builds

* "apt upgrade" is especially insidious because it means old versions of OS libraries could be leftover in your images

---

#### Can we do better?

---

#### What about Nix?
##### :snowflake: Enter flakes :snowflake: <!-- .element: class="fragment" -->

---
flake.nix
```nix
{
  description = "App to display cats telling fortunes";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";

    # Core pyproject-nix ecosystem tools
    pyproject-nix.url = "github:pyproject-nix/pyproject.nix";
    uv2nix.url = "github:pyproject-nix/uv2nix";
    pyproject-build-systems.url = "github:pyproject-nix/build-system-pkgs";

    # Ensure consistent dependencies between these tools
    pyproject-nix.inputs.nixpkgs.follows = "nixpkgs";
    uv2nix.inputs.nixpkgs.follows = "nixpkgs";
    pyproject-build-systems.inputs.nixpkgs.follows = "nixpkgs";
    uv2nix.inputs.pyproject-nix.follows = "pyproject-nix";
    pyproject-build-systems.inputs.pyproject-nix.follows = "pyproject-nix";
  };

  outputs = { self, nixpkgs, flake-utils, uv2nix, pyproject-nix, pyproject-build-systems, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        python = pkgs.python3; # Your desired Python version

        # 1. Load Project Workspace (parses pyproject.toml, uv.lock)
        workspace = uv2nix.lib.workspace.loadWorkspace {
          workspaceRoot = ./.; # Root of your flake/project
        };

        # 2. Generate Nix Overlay from uv.lock (via workspace)
        uvLockedOverlay = workspace.mkPyprojectOverlay {
          sourcePreference = "wheel"; # Or "sdist"
        };

        # 3. Placeholder for Your Custom Package Overrides
        myCustomOverrides = final: prev: {
          # e.g., some-package = prev.some-package.overridePythonAttrs (...); */
        };

        # 4. Construct the Final Python Package Set
        pythonSet =
          (pkgs.callPackage pyproject-nix.build.packages { inherit python; })
          .overrideScope (nixpkgs.lib.composeManyExtensions [
            pyproject-build-systems.overlays.default # For build tools
            uvLockedOverlay                          # Your locked dependencies
            myCustomOverrides                        # Your fixes
          ]);

        # --- This is where your project's metadata is accessed ---
        projectNameInToml = "build-demo"; # MUST match [project.name] in pyproject.toml!
        thisProjectAsNixPkg = pythonSet.${projectNameInToml};
        # ---

        # 5. Create the Python Runtime Environment
        appPythonEnv = pythonSet.mkVirtualEnv
          (thisProjectAsNixPkg.pname + "-env")
          workspace.deps.default; # Uses deps from pyproject.toml [project.dependencies]

        devPythonEnv = pythonSet.mkVirtualEnv
          (thisProjectAsNixPkg.pname + "-env")
          workspace.deps.dev; # Uses deps from pyproject.toml [project.dependencies]

      in
      {
        # Development Shell
        devShells.default = pkgs.mkShell {
          packages = [ devPythonEnv pkgs.uv ];
          shellHook = '' # Your custom shell hooks */ '';
        };

        # Nix Package for Your Application
        packages.default = pkgs.stdenv.mkDerivation {
          pname = thisProjectAsNixPkg.pname;
          version = thisProjectAsNixPkg.version;
          src = ./.; # Source of your main script

          nativeBuildInputs = [ pkgs.makeWrapper ];
          buildInputs = [ appPythonEnv ]; # Runtime Python environment

          installPhase = ''
            mkdir -p $out/bin
            cp main.py $out/bin/main.py
            cp ${pkgs.fortune}/bin/fortune $out/bin/fortune
            makeWrapper ${appPythonEnv}/bin/python $out/bin/${thisProjectAsNixPkg.pname} \
              --add-flags $out/bin/main.py \
              --set FORTUNE_EXEC $out/bin/fortune
          '';
        };
        packages.${thisProjectAsNixPkg.pname} = self.packages.${system}.default;

        # App for `nix run`
        apps.default = {
          type = "app";
          program = "${self.packages.${system}.default}/bin/${thisProjectAsNixPkg.pname}";
        };
        apps.${thisProjectAsNixPkg.pname} = self.apps.${system}.default;
      }
    );
}
```

Notes:

Totally straightforward, right?

-v-

# BUT WHY!?
<img src="https://the6track.com/wp-content/uploads/2017/10/Really-Confused-Black-guy-memes.jpg" class="r-stretch" />

-v-

flake.nix
```nix [52|82-90]
{
  description = "App to display cats telling fortunes";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";

    # Core pyproject-nix ecosystem tools
    pyproject-nix.url = "github:pyproject-nix/pyproject.nix";
    uv2nix.url = "github:pyproject-nix/uv2nix";
    pyproject-build-systems.url = "github:pyproject-nix/build-system-pkgs";

    # Ensure consistent dependencies between these tools
    pyproject-nix.inputs.nixpkgs.follows = "nixpkgs";
    uv2nix.inputs.nixpkgs.follows = "nixpkgs";
    pyproject-build-systems.inputs.nixpkgs.follows = "nixpkgs";
    uv2nix.inputs.pyproject-nix.follows = "pyproject-nix";
    pyproject-build-systems.inputs.pyproject-nix.follows = "pyproject-nix";
  };

  outputs = { self, nixpkgs, flake-utils, uv2nix, pyproject-nix, pyproject-build-systems, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        python = pkgs.python3; # Your desired Python version

        # 1. Load Project Workspace (parses pyproject.toml, uv.lock)
        workspace = uv2nix.lib.workspace.loadWorkspace {
          workspaceRoot = ./.; # Root of your flake/project
        };

        # 2. Generate Nix Overlay from uv.lock (via workspace)
        uvLockedOverlay = workspace.mkPyprojectOverlay {
          sourcePreference = "wheel"; # Or "sdist"
        };

        # 3. Placeholder for Your Custom Package Overrides
        myCustomOverrides = final: prev: {
          # e.g., some-package = prev.some-package.overridePythonAttrs (...); */
        };

        # 4. Construct the Final Python Package Set
        pythonSet =
          (pkgs.callPackage pyproject-nix.build.packages { inherit python; })
          .overrideScope (nixpkgs.lib.composeManyExtensions [
            pyproject-build-systems.overlays.default # For build tools
            uvLockedOverlay                          # Your locked dependencies
            myCustomOverrides                        # Your fixes
          ]);

        # --- This is where your project's metadata is accessed ---
        projectNameInToml = "build-demo"; # MUST match [project.name] in pyproject.toml!
        thisProjectAsNixPkg = pythonSet.${projectNameInToml};
        # ---

        # 5. Create the Python Runtime Environment
        appPythonEnv = pythonSet.mkVirtualEnv
          (thisProjectAsNixPkg.pname + "-env")
          workspace.deps.default; # Uses deps from pyproject.toml [project.dependencies]

        devPythonEnv = pythonSet.mkVirtualEnv
          (thisProjectAsNixPkg.pname + "-env")
          workspace.deps.dev; # Uses deps from pyproject.toml [project.dependencies]

      in
      {
        # Development Shell
        devShells.default = pkgs.mkShell {
          packages = [ devPythonEnv pkgs.uv ];
          shellHook = '' # Your custom shell hooks */ '';
        };

        # Nix Package for Your Application
        packages.default = pkgs.stdenv.mkDerivation {
          pname = thisProjectAsNixPkg.pname;
          version = thisProjectAsNixPkg.version;
          src = ./.; # Source of your main script

          nativeBuildInputs = [ pkgs.makeWrapper ];
          buildInputs = [ appPythonEnv ]; # Runtime Python environment

          installPhase = ''
            mkdir -p $out/bin
            cp main.py $out/bin/main.py
            cp ${pkgs.fortune}/bin/fortune $out/bin/fortune
            makeWrapper ${appPythonEnv}/bin/python $out/bin/${thisProjectAsNixPkg.pname} \
              --add-flags $out/bin/main.py \
              --set FORTUNE_EXEC $out/bin/fortune
          '';
        };
        packages.${thisProjectAsNixPkg.pname} = self.packages.${system}.default;

        # App for `nix run`
        apps.default = {
          type = "app";
          program = "${self.packages.${system}.default}/bin/${thisProjectAsNixPkg.pname}";
        };
        apps.${thisProjectAsNixPkg.pname} = self.apps.${system}.default;
      }
    );
}
```
