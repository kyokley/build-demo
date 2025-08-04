ARG BASE_IMAGE=python:3.13-slim

FROM ${BASE_IMAGE} AS base
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV PYTHONPATH=.
ENV UV_FROZEN=true
ENV UV_PROJECT_ENVIRONMENT=/venv
ENV UV_CACHE_DIR=/uv_cache
ENV UV_PROJECT_DIR=${UV_PROJECT_ENVIRONMENT}
ENV VIRTUAL_ENV=${UV_PROJECT_ENVIRONMENT}
ENV PATH="$VIRTUAL_ENV/bin:$PATH:/usr/games"

FROM base AS builder

RUN pip install --upgrade --no-cache-dir pip uv && \
        uv venv --seed ${VIRTUAL_ENV}

COPY uv.lock pyproject.toml ${UV_PROJECT_DIR}/

RUN uv sync --project ${VIRTUAL_ENV}

FROM base AS prod

RUN apt-get update && \
        apt-get install -y --no-install-recommends fortune fortunes && \
        pip install --upgrade --no-cache-dir pip uv

COPY --from=builder ${VIRTUAL_ENV} ${VIRTUAL_ENV}
COPY . ${UV_PROJECT_DIR}

WORKDIR ${UV_PROJECT_DIR}
