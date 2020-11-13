#!/bin/bash

PROJECT_CONTAINER=$(basename $PWD)

COLOR_DEFAULT=`tput sgr0`
COLOR_HIGHLIGHT=`tput setaf 75; tput bold`
COLOR_LINK=`tput setaf 219`
COLOR_SUCCESS=`tput setaf 42`

set -e

echo "Starting post-install operations...\n"

# Check if Docker is installed on the host system.
if ! [ -x "$(command -v docker)" ]; then
    echo "${COLOR_HIGHLIGHT}Docker is required for this package to run.\n${COLOR_DEFAULT}To learn more, visit: ${COLOR_LINK}https://docs.docker.com/get-docker/${COLOR_DEFAULT}"

    exit 1
fi

# Check if Composer is installed on the host system.
if ! hash composer; then
    echo "${COLOR_HIGHLIGHT}Composer is required for this package to run."

    read -p "${COLOR_DEFAULT}Would you like to install Composer locally? [Y/n] " -n 1 -r

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "\nInstalling Composer...\n"

        EXPECTED_CHECKSUM="$(wget -q -O - https://composer.github.io/installer.sig)"

        php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"

        ACTUAL_CHECKSUM="$(php -r "echo hash_file('sha384', 'composer-setup.php');")"

        if [ "$EXPECTED_CHECKSUM" != "$ACTUAL_CHECKSUM" ]; then
            >&2 echo 'ERROR: Invalid installer checksum!'

            rm composer-setup.php

            exit 1
        fi

        php composer-setup.php

        rm composer-setup.php

        if [ ! -d "./_lib/composer" ]; then
            mkdir -p ./_lib/composer;
        fi

        chmod a+x composer.phar

        mv composer.phar ./_lib/composer/composer.phar
    else
        echo "\nComposer not installed. Exiting post-install..."

        exit 1
    fi
fi

# Check and set development environment variables.
if ! [ -e "./.env" ]; then
    cp ./_lib/init/.env.default ./.env

    read -p "Set the local development url (default: spark.test): " -r LOCAL_URL

    if ! [[ -z "$LOCAL_URL" ]]; then
        sed -i "" "s/^LOCAL_URL=.*$/LOCAL_URL=${LOCAL_URL}/" .env
    fi

    read -p "Set the theme slug (default: spark-wp): " -r THEME_SLUG

    if ! [[ -z "$THEME_SLUG" ]]; then
        sed -i "" "s/^THEME_SLUG=.*$/THEME_SLUG=${THEME_SLUG}/" .env
    fi

    read -p "Choose specific WordPress version (leave blank for latest - fpm-alpine): " -r WORDPRESS_VERSION

    if ! [[ -z "$WORDPRESS_VERSION" ]]; then
        sed -i "" "s/^WORDPRESS_VERSION=.*$/WORDPRESS_VERSION=${WORDPRESS_VERSION}/" .env
    fi

    read -p "Set MySQL root password (blank for randomly generated): " -r MYSQL_ROOT_PASSWORD

    if ! [[ -z "$MYSQL_ROOT_PASSWORD" ]]; then
        sed -i "" "s/^MYSQL_ROOT_PASSWORD=.*$/MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD}/" .env
    else
        RANDOM_PASSWORD=$(sed "s/[^a-zA-Z0-9]//g" <<< $(openssl rand -base64 16))

        sed -i "" "s/^MYSQL_ROOT_PASSWORD=.*$/MYSQL_ROOT_PASSWORD=${RANDOM_PASSWORD}/" .env
    fi

    read -p "Set WordPress MySQL username (default: spark): " -r MYSQL_USER

    if ! [[ -z "$MYSQL_USER" ]]; then
        sed -i "" "s/^MYSQL_USER=.*$/MYSQL_USER=${MYSQL_USER}/" .env
    fi

    read -p "Set WordPress MySQL password (blank for randomly generated): " -r MYSQL_PASSWORD

    if ! [[ -z "$MYSQL_PASSWORD" ]]; then
        sed -i "" "s/^MYSQL_PASSWORD=.*$/MYSQL_PASSWORD=${MYSQL_PASSWORD}/" .env
    else
        RANDOM_PASSWORD=$(sed "s/[^a-zA-Z0-9]//g" <<< $(openssl rand -base64 16))

        sed -i "" "s/^MYSQL_PASSWORD=.*$/MYSQL_PASSWORD=${RANDOM_PASSWORD}/" .env
    fi

    read -p "Set ACF Pro URL: " -r ACF_PRO_URL

    if ! [[ -z "$ACF_PRO_URL" ]]; then
        sed -i "" "s|^ACF_PRO_URL=.*$|ACF_PRO_URL=${ACF_PRO_URL}|" .env
    fi
fi

# Clear existing Docker containers.
echo "Removing existing Docker containers and volumes if they exist...\n"

if [ "$(docker ps -aq -f name=db)" ]; then
    docker rm -f db
fi

if [ "$(docker ps -aq -f name=phpmyadmin)" ]; then
    docker rm -f phpmyadmin
fi

if [ "$(docker ps -aq -f name=wordpress)" ]; then
    docker rm -f wordpress
fi

if [ "$(docker ps -aq -f name=webserver)" ]; then
    docker rm -f webserver
fi

if [ "$(docker network ls -f name=${PROJECT_CONTAINER}_app-network)" ]; then
    docker network rm ${PROJECT_CONTAINER}_app-network
fi

if [ "$(docker volume ls -f name=${PROJECT_CONTAINER}_wordpress)" ]; then
    docker volume rm ${PROJECT_CONTAINER}_wordpress
fi

if [ "$(docker volume ls -f name=${PROJECT_CONTAINER}_dbdata)" ]; then
    docker volume rm ${PROJECT_CONTAINER}_dbdata
fi

# Create Docker containers.
echo "\nCreating docker containers...\n"

docker-compose up -d

echo "\n${COLOR_SUCCESS}Docker containers created!${COLOR_DEFAULT}\n"

# Delete WordPress' default plugins.
echo "Removing default plugins..."

shopt -s extglob
rm -rf ./wp-content/plugins/!(index.php)

# Install Composer requirements.
echo "Installing Composer dependencies...\n"

if [ -e "./_lib/composer/composer.phar" ]; then
    ./_lib/composer/composer.phar install
else
    composer install
fi

# Finish and exit script.
echo "\n${COLOR_SUCCESS}$(tput bold)Post-install operations have been completed, happy coding!"
