# development tree watchdog
# handles -march= / -mtune= architecture-specific distribution

FROM python:3.13-slim AS builder

RUN apt-get update                             \
&&  apt-get install -y --no-install-recommends \
    binutils                                   \
    gcc                                        \
    g++                                        \
    git                                        \
    libc6-dev                                  \
    llvm                                       \
    debhelper                                  \
    devscripts                                 \
    dpkg-dev                                   \
    build-essential                            \
&&  rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir \
    build                      \
    cython                     \
    httpx                      \
    setuptools                 \
    watchdog

COPY . /app
WORKDIR /app
ENV SETUPTOOLS_SCM_PRETEND_VERSION_FOR_IA=0.0.0

ENV PYTHONPATH="/app"
RUN pip install --no-cache-dir .
#RUN python -m build --wheel --outdir /dist
#
#FROM python:3.13-slim
#WORKDIR /app
#COPY --from=builder /dist/*.whl .
#RUN pip install --no-cache-dir *.whl \
#&&  rm -v *.whl

ENTRYPOINT ["python", "-u", "-m", "development_tree_watchdog"]
