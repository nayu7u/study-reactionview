# ARG stays behind .ruby-version until the 4.0.10 devcontainer image is
# published (checked 2026-11-19); .ruby-version wins.
ARG RUBY_VERSION=4.0.9
FROM ghcr.io/rails/devcontainer/images/ruby:$RUBY_VERSION

# Ensure binding is always 0.0.0.0
# Binds the server to all IP addresses of the container, so it can be accessed from outside the container.
ENV BINDING="0.0.0.0"
