# Staging rehearsal image: the committed tree on top of verify.Dockerfile, with the production steps of
# docker/Dockerfile (RAILS_ENV=production, assets:precompile, spec/node_modules/tmp cache removed).
# NOT the production image: production is built with docker/Dockerfile.
#   git archive <sha> | tar -x -C ctx && git rev-parse <sha> > ctx/.git_sha
#   docker build -f staging.Dockerfile --build-arg BASE=lynomia/verify:<sha> -t lynomia/staging:<sha> ctx
ARG BASE
FROM ${BASE}
ENV RAILS_ENV=production NODE_ENV=production RAILS_SERVE_STATIC_FILES=true EXECJS_RUNTIME=Disabled VIPS_BLOCK_UNTRUSTED=1
WORKDIR /app
RUN find /app -mindepth 1 -maxdepth 1 ! -name node_modules -exec rm -rf {} +
COPY . /app
RUN mkdir -p /app/log /app/tmp \
  && SECRET_KEY_BASE=precompile_placeholder RAILS_LOG_TO_STDOUT=enabled bundle exec rake assets:precompile \
  && rm -rf spec node_modules tmp/cache
