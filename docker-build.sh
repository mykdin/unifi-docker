#!/usr/bin/env bash

# fail on error
set -e

if [ "x${1}" == "x" ]; then
    echo please pass PKGURL as an environment variable
    exit 0
fi

apt-get update
apt-get install -qy --no-install-recommends \
    apt-transport-https \
    ca-certificates \
    curl \
    dirmngr \
    gpg \
    gpg-agent \
    wget

# Java 25 — UniFi 10.3+ .deb depends on temurin-25-jre (or equivalent); Bookworm/Ubuntu LTS repos do not ship it.
curl -fsSL https://packages.adoptium.net/artifactory/api/gpg/key/public \
    | gpg --dearmor -o /etc/apt/trusted.gpg.d/adoptium.gpg
. /etc/os-release
ADOPTIUM_CODENAME="${VERSION_CODENAME}"
if [ "${ID}" = "ubuntu" ] && [ -n "${UBUNTU_CODENAME:-}" ]; then
    ADOPTIUM_CODENAME="${UBUNTU_CODENAME}"
fi
echo "deb https://packages.adoptium.net/artifactory/deb ${ADOPTIUM_CODENAME} main" \
    | tee /etc/apt/sources.list.d/adoptium.list

# HTTPS key fetch — HKP keyservers often fail under buildx/QEMU (gpg exits 2: no dirmngr / timeout).
mkdir -p /usr/share/keyrings
curl -fsSL 'https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x06E85760C0A52C50' \
    | gpg --dearmor -o /usr/share/keyrings/ubiquiti-unifi.gpg
echo 'deb [signed-by=/usr/share/keyrings/ubiquiti-unifi.gpg] https://www.ui.com/downloads/unifi/debian stable ubiquiti' \
    | tee /etc/apt/sources.list.d/100-ubnt-unifi.list

# MongoDB is not in Debian/Ubuntu base repos at the version UniFi needs, so add MongoDB's apt repo.
# unifi requires mongodb-org-server >= 3.6.0 and < 8.1.0; MongoDB 8.0.x satisfies that.
MONGO_VERSION=8.0
case "$(dpkg --print-architecture)" in
    amd64|arm64)
        curl -fsSL "https://www.mongodb.org/static/pgp/server-${MONGO_VERSION}.asc" \
            | gpg --dearmor -o "/usr/share/keyrings/mongodb-server-${MONGO_VERSION}.gpg"
        if [ "${ID}" = "debian" ]; then
            echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-${MONGO_VERSION}.gpg ] https://repo.mongodb.org/apt/debian ${VERSION_CODENAME}/mongodb-org/${MONGO_VERSION} main" \
                > /etc/apt/sources.list.d/mongodb-org-${MONGO_VERSION}.list
        else
            echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-${MONGO_VERSION}.gpg ] https://repo.mongodb.org/apt/ubuntu ${UBUNTU_CODENAME}/mongodb-org/${MONGO_VERSION} multiverse" \
                > /etc/apt/sources.list.d/mongodb-org-${MONGO_VERSION}.list
        fi
        ;;
esac

if [ -d "/usr/local/docker/pre_build/$(dpkg --print-architecture)" ]; then
    find "/usr/local/docker/pre_build/$(dpkg --print-architecture)" -type f -exec '{}' \;
fi

apt-get update
apt-get install -qy --no-install-recommends \
    libcap2-bin \
    procps \
    temurin-25-jre \
    tzdata

curl -L -o ./unifi.deb "${1}"
# --no-install-recommends keeps the image lean and avoids pulling in
# systemd-resolved (a Recommends of systemd), whose postinst tries to replace
# the bind-mounted /etc/resolv.conf during `docker build` and fails noisily.
apt -qy install --no-install-recommends ./unifi.deb
rm -f ./unifi.deb
chown -R unifi:unifi /usr/lib/unifi
rm -rf /var/lib/apt/lists/*

rm -rf ${ODATADIR} ${OLOGDIR} ${ORUNDIR} ${BASEDIR}/data ${BASEDIR}/run ${BASEDIR}/logs
mkdir -p ${DATADIR} ${LOGDIR} ${RUNDIR}
ln -s ${DATADIR} ${BASEDIR}/data
ln -s ${RUNDIR} ${BASEDIR}/run
ln -s ${LOGDIR} ${BASEDIR}/logs
ln -s ${DATADIR} ${ODATADIR}
ln -s ${LOGDIR} ${OLOGDIR}
ln -s ${RUNDIR} ${ORUNDIR}
mkdir -p /var/cert ${CERTDIR}
ln -s ${CERTDIR} /var/cert/unifi

rm -rf "${0}"
