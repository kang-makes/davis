###############################################################
# Run update, and gets basic packages and packages for runtime
FROM php:8.2-fpm-alpine AS base-image

RUN apk --no-progress --update add --no-cache \
    curl unzip \
    # These are for php-intl
    icu-libs \
    # This one is for IMAP (to provide libc-client.so)
    c-client \
    # This one for LDAP
    libldap \
    # These are for GD (map image in mail)
    freetype \
    libjpeg-turbo \
    libpng \
    # This is for PostgreSQL
    libpq \
    # For the webserver and process manager
    caddy supervisor


###########################################################################
# Build all extension on a diferent build environment so keep things clean
FROM base-image AS extension-builder

RUN apk --update --no-cache add\
    # Intl support
    --virtual build-deps-intl \
    icu-dev \
    # PDO: PostgreSQL
    --virtual build-deps-pg \
    libpq-dev \
    # # PDO: PostgreSQL
    --virtual build-deps-pg libpq-dev \
    # GD (map image in mail)
    --virtual build-deps-gd \
    freetype-dev \
    libjpeg-turbo-dev \
    libpng-dev \
    # LDAP auth support
    --virtual build-deps-ldap \
    openldap-dev \
    # IMAP auth support
    --virtual build-deps-imap \
    imap-dev \
    openssl-dev \
    krb5-dev

# Leaving a Docker layer per extension so in case it fails I have it cached to develop faster. 

# Intl support
RUN docker-php-ext-install intl
# PDO: MySQL
RUN docker-php-ext-configure pdo_mysql --with-pdo-mysql=mysqlnd && \
    docker-php-ext-install pdo_mysql
# PDO: PostgreSQL
RUN docker-php-ext-configure pgsql --with-pgsql=/usr/local/pgsql && \
    docker-php-ext-install pgsql pdo_pgsql
# GD (map image in mail)
RUN docker-php-ext-configure gd --with-freetype && \
    docker-php-ext-install gd && \
    docker-php-ext-enable gd
# LDAP auth support
RUN docker-php-ext-configure ldap && \
    docker-php-ext-install ldap
# IMAP auth support
RUN docker-php-ext-configure imap --with-kerberos --with-imap-ssl && \
    docker-php-ext-install imap


###################################################
# Installing composer and downloading dependencies
FROM extension-builder AS composer

# Install Composer 2, then dependencies
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
ADD --chown=www-data:www-data . /var/www/davis/
WORKDIR /var/www/davis
RUN APP_ENV=prod COMPOSER_ALLOW_SUPERUSER=1 composer install --no-ansi --no-dev --no-interaction --no-progress --optimize-autoloader


###################################################
# Final image
FROM base-image

# https://github.com/docker-library/php/blob/master/8.2/alpine3.18/fpm/Dockerfile#L33
ARG fpm_user=82:82
ENV FPM_USER=${fpm_user}

COPY --from=extension-builder /usr/local/etc/php/conf.d     /usr/local/etc/php/conf.d/
COPY --from=extension-builder /usr/local/lib/php/extensions /usr/local/lib/php/extensions/
COPY --from=composer          /var/www/davis/vendor         /var/www/davis/vendor/

ADD --chown=$FPM_USER bin migrations public src /var/www/davis/
USER $FPM_USER
