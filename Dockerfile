FROM kong:2.3.0 as builder

USER root

RUN apk add --no-cache git zip && \
    git config --global url.https://github.com/.insteadOf git://github.com/

# Build kong-plugin-soap2rest
COPY . /plugins/soap2rest

WORKDIR /plugins/soap2rest

ENV LUAROCKS_SOAP2REST=kong-plugin-soap2rest
ENV LUAROCKS_SOAP2REST_VERSION=1.0.2-1

RUN luarocks make && \
    luarocks pack ${LUAROCKS_SOAP2REST} ${LUAROCKS_SOAP2REST_VERSION}

FROM kong:2.3.0

# Enable plugins
ENV KONG_PLUGINS="bundled,soap2rest"
ENV JWT_KEYCLOAK_PRIORITY="900"

COPY --from=builder /plugins/soap2rest/kong-plugin-soap2rest*.rock /tmp/plugins/

USER root

# Install plugins
RUN luarocks install /tmp/plugins/kong-plugin-soap2rest*.rock && \
    rm /tmp/plugins/*