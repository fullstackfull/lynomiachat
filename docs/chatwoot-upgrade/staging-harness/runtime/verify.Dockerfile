# Lynomia runtime verification image: Ruby 3.4.4 + Node 24.13.0 + pnpm 10.2.0 (the versions pinned by the repo),
# with the repo's own Gemfile.lock and pnpm-lock.yaml. Used to run the suites and the staging rehearsal where the
# Alpine package mirror needed by docker/Dockerfile is unreachable.
# NOT the production image: production is built with docker/Dockerfile.
#   docker build -f docs/chatwoot-upgrade/staging-harness/runtime/verify.Dockerfile -t lynomia/verify:<sha> .
FROM ruby:3.4.4-bookworm AS ruby
FROM node:24.13.0-bookworm-slim AS node
FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8 LC_ALL=C.UTF-8
RUN apt-get update && apt-get install -y --no-install-recommends build-essential git curl ca-certificates libpq-dev \
    postgresql-client libvips42 libyaml-dev libffi-dev libssl-dev zlib1g-dev libgmp-dev libreadline-dev tzdata \
    imagemagick shared-mime-info && rm -rf /var/lib/apt/lists/*
COPY --from=ruby /usr/local/ /usr/local/
COPY --from=node /usr/local/bin/node /usr/local/bin/node
COPY --from=node /usr/local/lib/node_modules /usr/local/lib/node_modules
ENV GEM_HOME=/usr/local/bundle BUNDLE_SILENCE_ROOT_WARNING=1 BUNDLE_APP_CONFIG=/usr/local/bundle PATH=/usr/local/bundle/bin:/usr/local/bin:$PATH
RUN ln -sf ../lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm && ln -sf ../lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx \
  && npm install -g pnpm@10.2.0 && ruby -v && node -v && pnpm -v && bundle -v
WORKDIR /app
COPY Gemfile Gemfile.lock ./
RUN bundle install -j 4 -r 3
COPY package.json pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile --ignore-scripts
COPY . /app
