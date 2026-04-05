FROM curlimages/curl AS oc_client
ARG OPENSHIFT_VERSION
ENV OPENSHIFT_VERSION="${OPENSHIFT_VERSION:-4.19}"
ENV OPENSHIFT_BINARIES_URL="https://mirror.openshift.com/pub/openshift-v4/clients/ocp/${OPENSHIFT_VERSION}"
RUN \
  url="${OPENSHIFT_BINARIES_URL}/openshift-client-linux"; \
  uname -m | grep -Eq 'arm|aarch' && url="${url}-arm64"; \
  curl -o /tmp/file.tar.gz "${url}.tar.gz"
RUN tar -xvzf /tmp/file.tar.gz -C /tmp

FROM scratch
COPY --from=oc_client /tmp/oc /oc
ENTRYPOINT [ "/oc" ]
