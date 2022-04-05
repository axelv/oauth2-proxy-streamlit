# All builds should be done using the platform native to the build node to allow
#  cache sharing of the go mod download step.
# Go cross compilation is also faster than emulation the go compilation across
#  multiple platforms.
FROM --platform=linux/amd64 golang:1.16-buster AS builder

# Copy sources
WORKDIR $GOPATH/src/github.com/oauth2-proxy/oauth2-proxy

# Fetch dependencies
COPY go.mod go.sum ./
RUN go mod download

# Now pull in our code
COPY . .

# Arguments go here so that the previous steps can be cached if no external
#  sources have changed.
ARG VERSION

# Build binary and make sure there is at least an empty key file.
#  This is useful for GCP App Engine custom runtime builds, because
#  you cannot use multiline variables in their app.yaml, so you have to
#  build the key into the container and then tell it where it is
#  by setting OAUTH2_PROXY_JWT_KEY_FILE=/etc/ssl/private/jwt_signing_key.pem
#  in app.yaml instead.
# Set the cross compilation arguments based on the TARGETPLATFORM which is
#  automatically set by the docker engine.
RUN GOARCH=amd64 \
    printf "Building OAuth2 Proxy for arch ${GOARCH}\n" && \
    VERSION=${VERSION} make build && touch jwt_signing_key.pem

# Copy binary to debian-python3.9 image
FROM python:3.9-buster
COPY nsswitch.conf /etc/nsswitch.conf
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
COPY --from=builder /go/src/github.com/oauth2-proxy/oauth2-proxy/oauth2-proxy /bin/oauth2-proxy
COPY --from=builder /go/src/github.com/oauth2-proxy/oauth2-proxy/jwt_signing_key.pem /etc/ssl/private/jwt_signing_key.pem
# copy app related files
COPY app /app

WORKDIR /app
# install streamlit
RUN pip3 install --no-cache-dir -r requirements.txt

# optmize streamlit for prodcution
ENV STREAMLIT_SERVER_HEADLESS true
ENV STREAMLIT_SERVER_FILE_WATCHER_TYPE none

# setup supervisor to run the proxy
# RUN apt-get update && apt-get install -y supervisor
# RUN mkdir -p /var/log/supervisor
#COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf
RUN chmod 755 docker-entrypoint.sh

# run the demo app
ENTRYPOINT [ "./docker-entrypoint.sh" ]
