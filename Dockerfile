# syntax=docker/dockerfile:1

# renovate: datasource=github-releases packageName=librenms/librenms versioning=semver
ARG LIBRENMS_VERSION="26.8.1"
ARG ALPINE_VERSION="3.23"
ARG SYSLOGNG_VERSION="4.10.2-r1"
ARG GOSU_VERSION="1.17"
ARG PUID="1000"
ARG PGID="1000"

FROM tianon/gosu:${GOSU_VERSION} AS gosu

FROM crazymax/alpine-s6:${ALPINE_VERSION}-2.2.0.3
COPY --from=gosu /gosu /usr/local/bin/
RUN apk --update --no-cache add \
    busybox-extras \
    acl \
    bash \
    bind-tools \
    binutils \
    ca-certificates \
    coreutils \
    curl \
    file \
    fping \
    git \
    graphviz \
    imagemagick \
    ipmitool \
    iputils \
    libcap-utils \
    mariadb-client \
    monitoring-plugins \
    mtr \
    net-snmp \
    net-snmp-tools \
    nginx \
    nmap \
    openssl \
    openssh-client \
    perl \
    php84 \
    php84-cli \
    php84-ctype \
    php84-curl \
    php84-dom \
    php84-fileinfo \
    php84-fpm \
    php84-gd \
    php84-gmp \
    php84-iconv \
    php84-json \
    php84-ldap \
    php84-mbstring \
    php84-mysqlnd \
    php84-opcache \
    php84-openssl \
    php84-pdo \
    php84-pdo_mysql \
    php84-pecl-memcached \
    php84-pear \
    php84-phar \
    php84-posix \
    php84-session \
    php84-simplexml \
    php84-snmp \
    php84-sockets \
    php84-tokenizer \
    php84-xml \
    php84-xmlwriter \
    php84-zip \
    python3 \
    py3-pip \
    rrdtool \
    syslog-ng=${SYSLOGNG_VERSION} \
    ttf-dejavu \
    tzdata \
    util-linux \
    whois \
  && apk --update --no-cache add -t build-dependencies \
    build-base \
    make \
    mariadb-dev \
    musl-dev \
    python3-dev \
  && pip3 install --upgrade --break-system-packages pip \
  && pip3 install python-memcached mysqlclient --upgrade --break-system-packages \
  && curl -sSL https://getcomposer.org/installer | php -- --install-dir=/usr/bin --filename=composer \
  && apk del build-dependencies \
  && rm -rf /var/www/* /tmp/* \
  && echo "/usr/sbin/fping -6 \$@" > /usr/sbin/fping6 \
  && chmod +x /usr/sbin/fping6 \
  && chmod u+s,g+s \
    /bin/ping \
    /bin/ping6 \
    /usr/lib/monitoring-plugins/check_icmp \
  && setcap cap_net_raw+ep /usr/bin/nmap \
  && setcap cap_net_raw+ep /usr/sbin/fping \
  && setcap cap_net_raw+ep /usr/sbin/fping6 \
  && setcap cap_net_raw+ep /usr/lib/monitoring-plugins/check_icmp \
  && setcap cap_net_raw+ep /usr/lib/monitoring-plugins/check_ping

ENV S6_BEHAVIOUR_IF_STAGE2_FAILS="2" \
  LIBRENMS_PATH="/opt/librenms" \
  LIBRENMS_DOCKER="1" \
  TZ="UTC"

RUN addgroup -g ${PGID} librenms \
  && adduser -D -h /home/librenms -u ${PUID} -G librenms -s /bin/sh librenms \
  && curl -sSL https://raw.githubusercontent.com/librenms/librenms-agent/master/snmp/distro -o /usr/bin/distro \
  && chmod +x /usr/bin/distro

WORKDIR ${LIBRENMS_PATH}
RUN apk --update --no-cache add -t build-dependencies \
    build-base \
    linux-headers \
    musl-dev \
    python3-dev \
  && echo "Installing LibreNMS https://github.com/librenms/librenms.git#${LIBRENMS_VERSION}..." \
  && git clone --depth=1 --branch ${LIBRENMS_VERSION} https://github.com/librenms/librenms.git . \
  && pip3 install -r requirements.txt --upgrade --break-system-packages \
  && mkdir config.d \
  && cp config.php.default config.php \
  && cp snmpd.conf.example /etc/snmp/snmpd.conf \
  && sed -i '/runningUser/d' lnms \
  && echo "foreach (glob(\"/data/config/*.php\") as \$filename) include \$filename;" >> config.php \
  && echo "foreach (glob(\"${LIBRENMS_PATH}/config.d/*.php\") as \$filename) include \$filename;" >> config.php \
  && chown -R librenms:librenms ${LIBRENMS_PATH} \
  && su librenms -s /bin/sh -c "COMPOSER_CACHE_DIR=/tmp composer install --no-dev --no-interaction --no-ansi" \
  && apk del build-dependencies \
  && rm -rf .git \
    html/plugins/Test \
    doc/ \
    tests/ \
    /tmp/*

COPY rootfs /

EXPOSE 8000 514 514/udp 162 162/udp
VOLUME [ "/data" ]

LABEL org.opencontainers.image.title="LibreNMS" \
  org.opencontainers.image.description="Autodiscovering PHP/MySQL/SNMP based network monitoring" \
  org.opencontainers.image.url="https://www.librenms.org" \
  org.opencontainers.image.source="https://github.com/librenms/docker" \
  org.opencontainers.image.licenses="GPL-3.0-only"

HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
  CMD curl -f http://localhost:8000/api/v0/health || exit 1

STOPSIGNAL SIGTERM

USER librenms

ENTRYPOINT [ "/init" ]
