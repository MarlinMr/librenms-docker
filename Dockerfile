# syntax=docker/dockerfile:1

# renovate: datasource=github-releases packageName=librenms/librenms versioning=semver
ARG LIBRENMS_VERSION="26.8.1"
ARG ALPINE_VERSION="3.23"
ARG SYSLOGNG_VERSION="4.10.2-r1"
ARG GOSU_VERSION="1.19"
ARG PUID="1000"
ARG PGID="1000"

# Build stage
FROM crazymax/alpine-s6:${ALPINE_VERSION}-2.2.0.3 AS builder
ARG LIBRENMS_VERSION

RUN apk --update --no-cache add \
    git php84 php84-cli php84-phar php84-openssl php84-mbstring php84-xml php84-curl php84-zip \
    php84-pdo_mysql php84-gd php84-ldap php84-snmp php84-gmp php84-posix php84-session php84-iconv \
    php84-simplexml php84-dom php84-fileinfo php84-ctype php84-tokenizer php84-xmlwriter php84-mysqlnd \
    php84-opcache php84-pecl-memcached php84-pdo php84-pear \
    python3 py3-pip build-base linux-headers mariadb-dev musl-dev python3-dev \
  && curl -sSL https://getcomposer.org/installer | php -- --install-dir=/usr/bin --filename=composer

ENV LIBRENMS_PATH="/opt/librenms"
WORKDIR ${LIBRENMS_PATH}

RUN git clone --depth=1 --branch ${LIBRENMS_VERSION} https://github.com/librenms/librenms.git . \
  && --mount=type=cache,target=/root/.cache/pip \
     pip3 install -r requirements.txt --upgrade --break-system-packages \
  && mkdir config.d \
  && cp config.php.default config.php \
  && cp snmpd.conf.example /etc/snmp/snmpd.conf \
  && sed -i '/runningUser/d' lnms \
  && echo "foreach (glob(\"/data/config/*.php\") as \$filename) include \$filename;" >> config.php \
  && echo "foreach (glob(\"${LIBRENMS_PATH}/config.d/*.php\") as \$filename) include \$filename;" >> config.php

RUN --mount=type=cache,target=/tmp/composer-cache \
    COMPOSER_CACHE_DIR=/tmp/composer-cache composer install --no-dev --no-interaction --no-ansi \
  && rm -rf .git html/plugins/Test doc/ tests/

# Runtime stage
FROM crazymax/alpine-s6:${ALPINE_VERSION}-2.2.0.3
ARG GOSU_VERSION
ARG SYSLOGNG_VERSION

COPY --from=tianon/gosu:${GOSU_VERSION} /gosu /usr/local/bin/

RUN apk --update --no-cache add \
    busybox-extras acl bash bind-tools binutils ca-certificates coreutils curl file fping \
    graphviz imagemagick ipmitool iputils libcap-utils mariadb-client monitoring-plugins mtr \
    net-snmp net-snmp-tools nginx nmap openssl openssh-client perl \
    php84 php84-cli php84-ctype php84-curl php84-dom php84-fileinfo php84-fpm php84-gd php84-gmp \
    php84-iconv php84-json php84-ldap php84-mbstring php84-mysqlnd php84-opcache php84-openssl \
    php84-pdo php84-pdo_mysql php84-pecl-memcached php84-pear php84-phar php84-posix php84-session \
    php84-simplexml php84-snmp php84-sockets php84-tokenizer php84-xml php84-xmlwriter php84-zip \
    python3 py3-pip rrdtool syslog-ng=${SYSLOGNG_VERSION} ttf-dejavu tzdata util-linux whois \
  && rm -rf /var/www/* /tmp/* \
  && echo "/usr/sbin/fping -6 \$@" > /usr/sbin/fping6 && chmod +x /usr/sbin/fping6 \
  && chmod u+s,g+s /bin/ping /bin/ping6 /usr/lib/monitoring-plugins/check_icmp \
  && setcap cap_net_raw+ep /usr/bin/nmap /usr/sbin/fping /usr/sbin/fping6 \
     /usr/lib/monitoring-plugins/check_icmp /usr/lib/monitoring-plugins/check_ping

ENV S6_BEHAVIOUR_IF_STAGE2_FAILS="2" \
  LIBRENMS_PATH="/opt/librenms" \
  LIBRENMS_DOCKER="1" \
  TZ="UTC"

RUN addgroup -g ${PGID} librenms \
  && adduser -D -h /home/librenms -u ${PUID} -G librenms -s /bin/sh librenms \
  && curl -sSL https://raw.githubusercontent.com/librenms/librenms-agent/master/snmp/distro -o /usr/bin/distro \
  && chmod +x /usr/bin/distro

WORKDIR ${LIBRENMS_PATH}

COPY --from=builder --chown=librenms:librenms /opt/librenms /opt/librenms

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