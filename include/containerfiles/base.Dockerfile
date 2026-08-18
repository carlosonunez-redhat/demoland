FROM curlimages/curl AS oc_client
ARG OPENSHIFT_VERSION
ENV OPENSHIFT_VERSION="${OPENSHIFT_VERSION:-4.19}"
ENV OPENSHIFT_BINARIES_URL="https://mirror.openshift.com/pub/openshift-v4/clients/ocp/${OPENSHIFT_VERSION}"
RUN \
  url="${OPENSHIFT_BINARIES_URL}/openshift-client-linux"; \
  uname -m | grep -Eq 'arm|aarch' && url="${url}-arm64"; \
  curl -o /tmp/file.tar.gz "${url}.tar.gz"
RUN tar -xvzf /tmp/file.tar.gz -C /tmp

FROM curlimages/curl AS ytt
RUN arch=amd64; uname -m | grep -Eiq 'arm|aarch' && arch=arm64; \
    curl -Lo /tmp/ytt "https://github.com/carvel-dev/ytt/releases/download/v0.52.0/ytt-linux-$arch"
RUN chmod +x /tmp/ytt
RUN /tmp/ytt --version

FROM fedora:43 AS final
RUN dnf -y install yq jq openssh ssh-agent htpasswd bsdtar
COPY --from=oc_client /tmp/oc /usr/local/bin/oc
COPY --from=ytt /tmp/ytt /usr/local/bin/ytt
RUN ln -s /usr/local/bin/oc /oc
# Both the Google Cloud and AWS CLIs install a bunch of stuff that makes retrieving them in
# their own layers awkward.
RUN arch=x86_64; uname -m | grep -Eiq 'arm|aarch' && arch=aarch64; \
  cat >/etc/yum.repos.d/google-cloud-sdk.repo <<-EOF
[google-cloud-cli]
name=Google Cloud CLI
baseurl=https://packages.cloud.google.com/yum/repos/cloud-sdk-el9-$arch
enabled=1
gpgcheck=1
repo_gpgcheck=0
gpgkey=https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
EOF
RUN sudo dnf -y install libxcrypt-compat google-cloud-cli
RUN curl -L "https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip" | bsdtar -C /tmp -xf - && \
    chmod -R +x /tmp/aws && \
    /tmp/aws/install
