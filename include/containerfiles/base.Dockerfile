FROM curlimages/curl AS oc_client
ARG OPENSHIFT_VERSION
ENV OPENSHIFT_VERSION="${OPENSHIFT_VERSION:-4.19}"
ENV OPENSHIFT_BINARIES_URL="https://mirror.openshift.com/pub/openshift-v4/clients/ocp/${OPENSHIFT_VERSION}"
RUN \
  url="${OPENSHIFT_BINARIES_URL}/openshift-client-linux"; \
  uname -m | grep -Eq 'arm|aarch' && url="${url}-arm64"; \
  curl -o /tmp/file.tar.gz "${url}.tar.gz"
RUN tar -xvzf /tmp/file.tar.gz -C /tmp

FROM fedora:43 AS final
COPY --from=oc_client /tmp/oc /usr/local/bin/oc
RUN ln -s /usr/local/bin/oc /oc
RUN dnf -y install yq jq openssh ssh-agent htpasswd bsdtar
RUN arch=amd64; uname -m | grep -Eiq 'arm|aarch' && arch=arm64; \
    curl -Lo /usr/bin/ytt "https://github.com/carvel-dev/ytt/releases/download/v0.52.0/ytt-linux-$arch"
RUN chmod +x /usr/bin/ytt
RUN ytt --version
