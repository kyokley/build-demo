---
title: Nix Build
slides:
    separator_vertical: ^\s*-v-\s*$
---

# Nix Build

---

## Docker <!-- .element: class="fragment" -->
Is Docker a good platform for creating reproducible builds? <!-- .element: class="fragment" -->

---

According to [Docker](https://www.docker.com/why-docker/)
> Docker introduced what would become the industry standard for containers. Containers are a standardized unit of software that allows developers to isolate their app from its environment, solving the “it works on my machine” headache.

---

According to ChatGPT
> Docker provides a solid foundation for reproducible builds, especially compared to traditional “run this bash script on a VM” setups. However, true reproducibility requires discipline—Docker makes it possible, but you have to make it happen.

---

Can we do better?

---

Enter Fortune Cat :cat:
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


@app.get("/")
def main():
    return "Hello from build-demo!"


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

FROM base AS prod

RUN apt-get update && \
        apt-get install -y --no-install-recommends fortune fortunes && \
        pip install --upgrade --no-cache-dir pip uv

COPY --from=builder ${VIRTUAL_ENV} ${VIRTUAL_ENV}
COPY . ${UV_PROJECT_DIR}

WORKDIR ${UV_PROJECT_DIR}
```
-v-

Potential Issues :thinking:
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

FROM base AS prod

RUN apt-get update && \
        apt-get install -y --no-install-recommends fortune fortunes && \
        pip install --upgrade --no-cache-dir pip uv

COPY --from=builder ${VIRTUAL_ENV} ${VIRTUAL_ENV}
COPY . ${UV_PROJECT_DIR}

WORKDIR ${UV_PROJECT_DIR}
```
