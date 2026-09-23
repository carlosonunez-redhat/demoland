FROM demoland-base
RUN arch=x86_64; uname -m | grep -Eiq 'arm|aarch' && arch=aarch64; \
    curl -L "https://awscli.amazonaws.com/awscli-exe-linux-$arch.zip" | bsdtar -C /tmp -xf - && \
    chmod -R +x /tmp/aws && \
    /tmp/aws/install --update
