# https://github.com/docker-library/php/blob/master/8.2/alpine3.18/fpm/Dockerfile#L33
ARG fpm_user=82:82

###############################################################
# Run update, and gets basic packages and packages for runtime
FROM php:8.2-fpm-alpine AS base-image

RUN apk --no-progress --update add --no-cache \
    curl unzip \
    # Runtime dependencies
    # php-intl
    icu-libs \
    # PostgreSQL
    libpq \
    # GD (map image in mail)
    freetype \
    libjpeg-turbo \
    libpng \
    # LDAP
    libldap \
    # IMAP (provides libc-client.so)
    c-client

###########################################################################
# Build all extension on a diferent build environment so keep things clean
FROM base-image AS extension-builder

RUN apk --update --no-cache add \
    # Compilation dependencies
    # Intl
    --virtual build-deps-intl \
    icu-dev \
    # PostgreSQL
    --virtual build-deps-pg \
    libpq-dev \
    # GD (map image in mail)
    --virtual build-deps-gd \
    freetype-dev \
    libjpeg-turbo-dev \
    libpng-dev \
    # LDAP
    --virtual build-deps-ldap \
    openldap-dev \
    # IMAP
    --virtual build-deps-imap \
    imap-dev \
    openssl-dev \
    krb5-dev

# Leaving a Docker layer per extension so in case it fails I have it cached to develop faster.
# But we are also cleaning each layer so it does not grow to the point we get out of cache space.

# Intl support
RUN docker-php-ext-install -j$(nproc) intl && \
    docker-php-source delete && \
    rm -rf /tmp/*
# PDO: MySQL
RUN docker-php-ext-configure pdo_mysql --with-pdo-mysql=mysqlnd && \
    docker-php-ext-install -j$(nproc) pdo_mysql && \
    docker-php-source delete && \
    rm -rf /tmp/*
# PDO: PostgreSQL
RUN docker-php-ext-configure pgsql --with-pgsql=/usr/local/pgsql && \
    docker-php-ext-install -j$(nproc) pgsql pdo_pgsql && \
    docker-php-source delete && \
    rm -rf /tmp/*
# GD (map image in mail)
RUN docker-php-ext-configure gd --with-freetype && \
    docker-php-ext-install -j$(nproc) gd && \
    docker-php-ext-enable gd && \
    docker-php-source delete && \
    rm -rf /tmp/*
# LDAP auth support
RUN docker-php-ext-configure ldap && \
    docker-php-ext-install -j$(nproc) ldap && \
    docker-php-source delete && \
    rm -rf /tmp/*
# IMAP auth support
RUN docker-php-ext-configure imap --with-kerberos --with-imap-ssl && \
    docker-php-ext-install -j$(nproc) imap && \
    docker-php-source delete && \
    rm -rf /tmp/*


###################################################
# Installing composer and downloading dependencies
FROM extension-builder AS composer

# Install Composer 2, then dependencies
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
ADD --chown=www-data:www-data . /var/www/davis/
WORKDIR /var/www/davis
RUN APP_ENV=prod COMPOSER_ALLOW_SUPERUSER=1 composer install --no-ansi --no-dev --no-interaction --no-progress --optimize-autoloader


###################################################
# Image that composer all the build steps
FROM scratch AS squash-this-layer

COPY --from=extension-builder /usr/local/etc/php/conf.d     /usr/local/etc/php/conf.d/
COPY --from=extension-builder /usr/local/lib/php/extensions /usr/local/lib/php/extensions/
COPY --from=composer          /var/www/davis/vendor         /var/www/davis/vendor/

ADD --chown=$FPM_USER bin migrations public src /var/www/davis/

###################################################
# Final image
FROM base-image

COPY --from=squash-this-layer / /

USER $FPM_USER
