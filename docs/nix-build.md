---
title: Nix Build
slides:
    separator_vertical: ^\s*-v-\s*$
---

# :building_construction: Deterministic
# Deployments :ship:

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
:snake: main.py :snake:
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

-v-

#### :cat: Enter Fortune Cat :cat:
pyproject.toml

```
[project]
name = "build-demo"
version = "0.1.0"
description = "Fortune Cat!"
readme = "README.md"
requires-python = ">=3.13"
dependencies = [
    "fastapi>=0.116.1",
    "httpx>=0.28.1",
    "uvicorn>=0.35.0",
]
```

-v-

#### :cat: Enter Fortune Cat :cat:
```
fortune_cat
├── main.py
├── pyproject.toml
├── README.md
└── uv.lock
```

---

Let's build a container

---

:whale: Dockerfile :whale:
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
To build:
```bash
docker build -t kyokley/build-demo -f Dockerfile .
```
Notes:

What parts of this risk reproducibility?

-v-

:thinking: Potential Issues :thinking:
```dockerfile [1-32|1|25-27]
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
To build:
```bash
docker build -t kyokley/build-demo -f Dockerfile .
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
#### uv2nix
:snowflake: flake.nix :snowflake:
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

* Totally straightforward, right?
* It's only about 100 lines compared to the 34 for the Dockerfile

-v-

# BUT WHY!?
<img src="https://the6track.com/wp-content/uploads/2017/10/Really-Confused-Black-guy-memes.jpg" class="r-stretch" />

-v-

:snowflake: flake.nix :snowflake:
```nix [1-117|52|82-90]
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
          workspace.deps.all; # Uses deps from pyproject.toml [project.dependencies]

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
To run:
```bash
nix run .
```

Notes:

This is mostly boilerplate

Be sure to run :
```
nix build .
```
after nix run

---

### Great, now what???
How does this lead to reproducible builds?

---

:snowflake: flake.lock :snowflake:
```text
{
  "nodes": {
    "flake-utils": {
      "inputs": {
        "systems": "systems"
      },
      "locked": {
        "lastModified": 1731533236,
        "narHash": "sha256-l0KFg5HjrsfsO/JpG+r7fRrqm12kzFHyUHqHCVpMMbI=",
        "owner": "numtide",
        "repo": "flake-utils",
        "rev": "11707dc2f618dd54ca8739b309ec4fc024de578b",
        "type": "github"
      },
      "original": {
        "owner": "numtide",
        "repo": "flake-utils",
        "type": "github"
      }
    },
    "nixpkgs": {
      "locked": {
        "lastModified": 1753939845,
        "narHash": "sha256-K2ViRJfdVGE8tpJejs8Qpvvejks1+A4GQej/lBk5y7I=",
        "owner": "NixOS",
        "repo": "nixpkgs",
        "rev": "94def634a20494ee057c76998843c015909d6311",
        "type": "github"
      },
      "original": {
        "owner": "NixOS",
        "ref": "nixos-unstable",
        "repo": "nixpkgs",
        "type": "github"
      }
    },
    "pyproject-build-systems": {
      "inputs": {
        "nixpkgs": [
          "nixpkgs"
        ],
        "pyproject-nix": [
          "pyproject-nix"
        ],
        "uv2nix": "uv2nix"
      },
      "locked": {
        "lastModified": 1753063383,
        "narHash": "sha256-H+gLv6424OjJSD+l1OU1ejxkN/v0U+yaoQdh2huCXYI=",
        "owner": "pyproject-nix",
        "repo": "build-system-pkgs",
        "rev": "45888b7fd4bf36c57acc55f07917bdf49ec89ec9",
        "type": "github"
      },
      "original": {
        "owner": "pyproject-nix",
        "repo": "build-system-pkgs",
        "type": "github"
      }
    },
    "pyproject-nix": {
      "inputs": {
        "nixpkgs": [
          "nixpkgs"
        ]
      },
      "locked": {
        "lastModified": 1753773975,
        "narHash": "sha256-r0NuyhyLUeLe/kSr+u2VFGjHFdccBJckZyFt74MYL5A=",
        "owner": "pyproject-nix",
        "repo": "pyproject.nix",
        "rev": "62cc4495b3b2d2a259db321a06584378e93843a6",
        "type": "github"
      },
      "original": {
        "owner": "pyproject-nix",
        "repo": "pyproject.nix",
        "type": "github"
      }
    },
    "root": {
      "inputs": {
        "flake-utils": "flake-utils",
        "nixpkgs": "nixpkgs",
        "pyproject-build-systems": "pyproject-build-systems",
        "pyproject-nix": "pyproject-nix",
        "uv2nix": "uv2nix_2"
      }
    },
    "systems": {
      "locked": {
        "lastModified": 1681028828,
        "narHash": "sha256-Vy1rq5AaRuLzOxct8nz4T6wlgyUR7zLU309k9mBC768=",
        "owner": "nix-systems",
        "repo": "default",
        "rev": "da67096a3b9bf56a91d16901293e51ba5b49a27e",
        "type": "github"
      },
      "original": {
        "owner": "nix-systems",
        "repo": "default",
        "type": "github"
      }
    },
    "uv2nix": {
      "inputs": {
        "nixpkgs": [
          "pyproject-build-systems",
          "nixpkgs"
        ],
        "pyproject-nix": [
          "pyproject-build-systems",
          "pyproject-nix"
        ]
      },
      "locked": {
        "lastModified": 1752805696,
        "narHash": "sha256-GpqeCI2n6sSdIEY/vG9qbQOoN+4/ZcSEhnFeLXG/hxs=",
        "owner": "pyproject-nix",
        "repo": "uv2nix",
        "rev": "8c77cd2cb5a9693e26fb8579f6a25565d99e400d",
        "type": "github"
      },
      "original": {
        "owner": "pyproject-nix",
        "repo": "uv2nix",
        "type": "github"
      }
    },
    "uv2nix_2": {
      "inputs": {
        "nixpkgs": [
          "nixpkgs"
        ],
        "pyproject-nix": [
          "pyproject-nix"
        ]
      },
      "locked": {
        "lastModified": 1753775881,
        "narHash": "sha256-9G0Yo7TXFJEfSyHNrbV1WNEKhEojqQ3J0aWd0aYpixs=",
        "owner": "pyproject-nix",
        "repo": "uv2nix",
        "rev": "656928e823e305426200f478a887943a600db303",
        "type": "github"
      },
      "original": {
        "owner": "pyproject-nix",
        "repo": "uv2nix",
        "type": "github"
      }
    }
  },
  "root": "root",
  "version": 7
}
```

---

Query the Nix store
```bash
nix build .
nix-store -qR result
```

```text
/nix/store/19cmj1h0p5gb3nbadrgz301m4b3yrdgk-pydantic-2.11.7
/nix/store/n9mggs3wskqv3vqd4xn8hbq2yzcf2z1d-xgcc-14.3.0-libgcc
/nix/store/562jc9ym7vd1zsw6sbq7i6j1vg8k1x32-libunistring-1.3
/nix/store/v9rj8vr6q5j3kr9nmdwhc3mi7cg55xcs-libidn2-2.3.8
/nix/store/lmn7lwydprqibdkghw7wgcn21yhllz13-glibc-2.40-66
/nix/store/97jdzvwjgwy2g4xcijimadl0vpj6laqh-zlib-1.3.1
/nix/store/yd47pmkv6iv58gs5v5jgyblvkw87pqx3-sqlite-3.50.2
/nix/store/29f7lcljr566rb1cqf14a3rcjpajbg7i-util-linux-minimal-2.41-lib
/nix/store/4kark163478mlnx42k2gakrji1z43z9m-ncurses-6.5
/nix/store/57ybxmmsdz67prqnyqi4badmg59303i0-typing-inspection-0.4.1
/nix/store/5hc7drjs7yydabg1amrsma0g9dqi4358-typing-extensions-4.14.1
/nix/store/7ap0mfwsv7gnzvfjpymrj55pj2yc13sq-click-8.2.1
/nix/store/d30jzadpdsxdk7jwp7h3znrfr5gpf816-bzip2-1.0.8
/nix/store/cg41x0ldk43qlsndsbladyl0k4dxanvh-gcc-14.3.0-libgcc
/nix/store/fkw48vh7ivlvlmhp4j30hy2gvg00jgin-gcc-14.3.0-lib
/nix/store/gkwbw9nzbkbz298njbn3577zmrnglbbi-bash-5.3p0
/nix/store/l3pzyjc5zmzp4bcbg40s6f5zjq87c77i-gdbm-1.25-lib
/nix/store/lrzs7l92j20n81rv4hs5js5qigg686s3-xz-5.8.1
/nix/store/lsbw8y9k2sg13c7z1nrqgzmg42ln1ji2-mpdecimal-4.0.1
/nix/store/lyl9yxxz8a3mlaxvm0jln6mglpbf2fha-openssl-3.5.1
/nix/store/ms10flhvgnd1nsfwnb355aw414ijlq8j-tzdata-2025b
/nix/store/p23www756j3bjy9l1bf5bkwmr2vvd6h1-expat-2.7.1
/nix/store/qfz8slc34jinyfkvmskaplijj8a79w25-libffi-3.5.1
/nix/store/sdyl0b9k0ijgdfwba9cgp76m81nhm387-libxcrypt-4.4.38
/nix/store/sldk7q9f60pm7s9sr2ir9qmk5242ig6j-mailcap-2.1.54
/nix/store/wqg50ip92b4626ryk097yszg6lyi32bf-readline-8.3p1
/nix/store/9yh9ak97gn659bk4d3n411fx6c0ng7s2-python3-3.13.5
/nix/store/gqmidk0dajvm3hk123ynwd0zkl0vyxsr-httpx-0.28.1
/nix/store/h4m3a0knam7vggq878b4v28z716lmrv6-fastapi-0.116.1
/nix/store/kllanvd6azh2szl1mm13rc0xq570jdag-h11-0.16.0
/nix/store/mgl5a0lsbr23qvnz3cic112nk69z2qd2-idna-3.10
/nix/store/mk757arf4yd68kz1y6wzl5487slp89im-pydantic-core-2.33.2
/nix/store/psaj602f2bw22dv4kgl4b1b8wylrpxdp-certifi-2025.8.3
/nix/store/qwdivzbv1l08sxnak3hwykla44k11n7j-httpcore-1.0.9
/nix/store/rlmf7gy0i82jr0irgwjhdc39v1v9nlzi-anyio-4.9.0
/nix/store/v31f8n80w8jcckc5jpld9h0y54w3lkiv-uvicorn-0.35.0
/nix/store/vy1rpkxh98h9hrk1gsgwchclhm6bz29v-build-demo-0.1.0
/nix/store/w1cz89vn755frpv09b526y09jnpc27cw-starlette-0.47.2
/nix/store/wrlhpf30w8d4bhi7zdva58s5c4ri9inp-annotated-types-0.7.0
/nix/store/yg48ysghiif5gb47dml4rvjdxrpq7ch4-sniffio-1.3.1
/nix/store/lmldw4ch9mbpsjlypsjxy4sdq7amnjcy-build-demo-env
/nix/store/ma0amj322nxwgv18dc2l13vcjlsjfdaw-recode-3.7.14
/nix/store/v3ny8rcwhisjxfhkif4aykc0pcc7b2wx-fortune-mod-3.24.0
/nix/store/mgvcnprxflx5mj7yl5wk9af44w9srb34-build-demo-0.1.0
```

Notes:
So if Nix can show us this then...

---

#### Nix Dockerfile: Attempt #1
:whale: Dockerfile-nix :whale:
```dockerfile
# Nix builder
FROM nixos/nix:latest AS builder

# Copy our source and setup our working dir.
COPY . /tmp/build
WORKDIR /tmp/build

# Build our Nix environment
RUN nix \
    --extra-experimental-features "nix-command flakes" \
    --option filter-syscalls false \
    build

ENTRYPOINT ["result/bin/build-demo"]
```

-v-

To run:
```bash
docker build -t kyokley/build-demo-nix -f Dockerfile-nix .
docker run --rm -it \
           -p 127.0.0.1:8001:8001 \
           kyokley/build-demo-nix
```

---

#### Nix Dockerfile: Attempt #2
:whale: Dockerfile-nix :whale:
```dockerfile [1-17|19-29]
# Nix builder
FROM nixos/nix:latest AS builder

# Copy our source and setup our working dir.
COPY . /tmp/build
WORKDIR /tmp/build

# Build our Nix environment
RUN nix \
    --extra-experimental-features "nix-command flakes" \
    --option filter-syscalls false \
    build

# Copy the Nix store closure into a directory. The Nix store closure is the
# entire set of Nix store values that we need for our build.
RUN mkdir /tmp/nix-store-closure
RUN cp -R $(nix-store -qR result/) /tmp/nix-store-closure

# Final image is based on scratch. We copy a bunch of Nix dependencies
# but they're fully self-contained so we don't need Nix anymore.
FROM scratch

WORKDIR /result

# Copy /nix/store
COPY --from=builder /tmp/nix-store-closure /nix/store
COPY --from=builder /tmp/build/result /result

ENTRYPOINT ["/result/bin/build-demo"]
```

-v-

To run:
```bash
docker build -t kyokley/build-demo-nix2 -f Dockerfile-nix2 .
docker run --rm -it \
           -p 127.0.0.1:8001:8001 \
           kyokley/build-demo-nix2
```

---

#### Nix Docker: Attempt #3
:snowflake: Nix dockerTools.buildImage :snowflake:
```nix
# Add as output in flake.nix
packages.docker-image = pkgs.dockerTools.buildImage {
    name = "kyokley/build-demo-nix3";
    tag = "latest";
    copyToRoot = pkgs.buildEnv {
        name = "image-root";
        paths = [ self.packages.${system}.default ];
        pathsToLink = ["/bin"];
    };
    config = {
        Entrypoint = ["/bin/${thisProjectAsNixPkg.pname}"];
        Env = [
            "FORTUNE_EXEC=/bin/fortune"
        ];
    };
};
```

-v-

To run:
```bash
nix build '.#docker-image'
docker load < result
docker run --rm -it \
           -p 127.0.0.1:8001:8001 \
           kyokley/build-demo-nix3
```

-v-

#### Nix Docker: Attempt #3
:snowflake: Nix dockerTools.buildImage :snowflake:
```nix [100-114]
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
          workspace.deps.all; # Uses deps from pyproject.toml [project.dependencies]

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

        packages.docker-image = pkgs.dockerTools.buildImage {
          name = "kyokley/build-demo-nix3";
          tag = "latest";
          copyToRoot = pkgs.buildEnv {
            name = "image-root";
            paths = [ self.packages.${system}.default ];
            pathsToLink = ["/bin"];
          };
          config = {
            Entrypoint = ["/bin/${thisProjectAsNixPkg.pname}"];
            Env = [
              "FORTUNE_EXEC=/bin/fortune"
            ];
          };
        };
      }
    );
}
```
To run:
```bash
nix build '.#docker-image'
docker load < result
docker run --rm -it \
           -p 127.0.0.1:8001:8001 \
           kyokley/build-demo-nix3
```

---

### Docker :heart: Nix
