# syntax=docker/dockerfile:1
#
# AUTOMA GP — reproducible SBCL + Quicklisp environment.
#
#   docker build -t automa-gp .            # builds and runs the FiveAM suite
#   docker run --rm automa-gp              # runs the suite again
#   docker run --rm -it automa-gp sbcl     # REPL with automa-gp on the load path
#   docker run --rm -p 47391:47391 automa-gp ./scripts/run-web.sh
#
# Stage `base` holds the toolchain only and is what .devcontainer uses.
# Stage `test` copies the tree and runs ./scripts/run-tests.sh.

ARG DEBIAN_TAG=trixie-slim

FROM debian:${DEBIAN_TAG} AS base

ARG USERNAME=dev
ARG USER_UID=1000
ARG USER_GID=1000

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      sbcl ca-certificates curl git make \
 && rm -rf /var/lib/apt/lists/* \
 && groupadd --gid "${USER_GID}" "${USERNAME}" \
 && useradd --uid "${USER_UID}" --gid "${USER_GID}" --create-home --shell /bin/bash "${USERNAME}"

USER ${USERNAME}
ENV HOME=/home/${USERNAME}
WORKDIR ${HOME}

# Quicklisp under ~/quicklisp, loaded from ~/.sbclrc, with the libraries
# the three systems need already fetched and compiled.
RUN curl -fsSL https://beta.quicklisp.org/quicklisp.lisp -o /tmp/quicklisp.lisp \
 && sbcl --non-interactive \
      --load /tmp/quicklisp.lisp \
      --eval "(quicklisp-quickstart:install :path \"${HOME}/quicklisp/\")" \
      --eval '(ql-util:without-prompting (ql:add-to-init-file))' \
 && rm /tmp/quicklisp.lisp \
 && sbcl --non-interactive \
      --load "${HOME}/quicklisp/setup.lisp" \
      --eval "(ql:quickload '(\"fiveam\" \"hunchentoot\") :silent t)"

ENV AUTOMA_GP_WEB_PORT=47391
EXPOSE 47391

# ---------------------------------------------------------------------------
FROM base AS test

WORKDIR /workspaces/automa-gp
COPY --chown=${USER_UID}:${USER_GID} . .

# Put the tree on Quicklisp's load path so `(ql:quickload :automa-gp)` works
# in the image's REPL. scripts/run-tests.sh tests the checkout it lives in
# and exits non-zero when a test fails, which fails the image build.
RUN mkdir -p "${HOME}/quicklisp/local-projects" \
 && ln -sfn /workspaces/automa-gp "${HOME}/quicklisp/local-projects/automa-gp" \
 && ./scripts/run-tests.sh

CMD ["./scripts/run-tests.sh"]
