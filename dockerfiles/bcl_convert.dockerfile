FROM centos:7
# singularity exec --bind logs:/var/log/bcl-convert bcl-convert.sif bcl-convert --help

RUN sed -i s/mirror.centos.org/vault.centos.org/g /etc/yum.repos.d/CentOS-*.repo
RUN sed -i s/^#.*baseurl=http/baseurl=http/g /etc/yum.repos.d/CentOS-*.repo
RUN sed -i s/^mirrorlist=http/#mirrorlist=http/g /etc/yum.repos.d/CentOS-*.repo

# ADD bcl-convert.rpm /tmp/bcl-convert.rpm

# RUN yum install -y gdb && \
#     rpm -i /tmp/bcl-convert.rpm && \
#     rm /tmp/bcl-convert.rpm && \
#     yum clean all && \
#     rm -rf /var/cache/yum

# Install Google Cloud SDK (includes gsutil)
RUN yum install -y curl python3 unzip && \
    curl -O https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-sdk-468.0.0-linux-x86_64.tar.gz && \
    tar -xzf google-cloud-sdk-468.0.0-linux-x86_64.tar.gz && \
    ./google-cloud-sdk/install.sh --quiet && \
    rm google-cloud-sdk-468.0.0-linux-x86_64.tar.gz

# Add Cloud SDK to PATH
ENV PATH="/google-cloud-sdk/bin:$PATH"