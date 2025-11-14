FROM php:8.2-fpm-alpine

# Install essential runtime libraries
RUN apk add --no-cache \
    bash \
    curl \
    less \
    icu-libs \
    libzip \
    libpng \
    libjpeg-turbo \
    libwebp \
    freetype \
    libxml2 \
    oniguruma \
    tzdata \
    fcgi \
    imagemagick \
    libsodium

# Install build dependencies (.build-deps)
RUN apk add --no-cache --virtual .build-deps \
    $PHPIZE_DEPS \
    icu-dev \
    libzip-dev \
    libpng-dev \
    libjpeg-turbo-dev \
    libwebp-dev \
    freetype-dev \
    libxml2-dev \
    oniguruma-dev \
    curl-dev \
    imagemagick-dev \
    libsodium-dev


# Install PHP extensions (for WP + Woo + Divi + Redis)

RUN docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp \
 && docker-php-ext-install -j"$(nproc)" \
    mysqli \
    pdo_mysql \
    intl \
    zip \
    gd \
    exif \
    bcmath \
    opcache \
    mbstring \
    soap \
    curl \
    sodium

# Redis & Imagick extensions (PECL)
RUN pecl install redis imagick\
 && docker-php-ext-enable redis imagick


# Remove build dependencies
RUN apk del .build-deps

# Install WP-CLI for WordPress management
RUN curl -fsSL https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar -o /usr/local/bin/wp \
 && chmod +x /usr/local/bin/wp

# PHP basic settings
# Upload/memory limits can be overridden by volume mounts in compose
RUN { \
    echo "upload_max_filesize = 128M"; \
    echo "post_max_size = 128M"; \
    echo "memory_limit = 512M"; \
    echo "max_execution_time = 300"; \
    echo "date.timezone = Pacific/Honolulu"; \
} > /usr/local/etc/php/conf.d/uploads.ini

# Opcache settings (performance improvement)
RUN { \
    echo "opcache.enable=1"; \
    echo "opcache.memory_consumption=128"; \
    echo "opcache.max_accelerated_files=20000"; \
    echo "opcache.validate_timestamps=1"; \
    echo "opcache.revalidate_freq=2"; \
} > /usr/local/etc/php/conf.d/opcache.ini

# Basic directory and permissions
WORKDIR /var/www/html
