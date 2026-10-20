#!/bin/bash
# --------------------------------------------------------------------
#
# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements. See the NOTICE file distributed
# with this work for additional information regarding copyright
# ownership. The ASF licenses this file to You under the Apache
# License, Version 2.0 (the "License"); you may not use this file
# except in compliance with the License. You may obtain a copy of the
# License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
# implied. See the License for the specific language governing
# permissions and limitations under the License.
#
# --------------------------------------------------------------------
set -euo pipefail

# Cloudberry DEB Package Build Script for Ubuntu 22.04 and 26.04
CLOUDBERRY_VERSION="${CLOUDBERRY_VERSION:-99.0.0}"
CLOUDBERRY_BUILD="${CLOUDBERRY_BUILD:-1}"
INSTALL_PREFIX="${INSTALL_PREFIX:-/usr/local/cloudberry-db}"
WORKSPACE="${WORKSPACE:-$HOME/workspace}"
CLOUDBERRY_SRC="${WORKSPACE}/cloudberry"

echo "=== Cloudberry DEB Package Build ==="
echo "Version: ${CLOUDBERRY_VERSION}"
echo "Build: ${CLOUDBERRY_BUILD}"
echo "Install Prefix: ${INSTALL_PREFIX}"
echo "Source: ${CLOUDBERRY_SRC}"

# Clean previous installation
rm -rf "${INSTALL_PREFIX}"
mkdir -p "${INSTALL_PREFIX}"

# Build Cloudberry using official build scripts
export SRC_DIR="${CLOUDBERRY_SRC}"
mkdir -p "${SRC_DIR}/build-logs"
cd "${CLOUDBERRY_SRC}"
./devops/build/automation/cloudberry/scripts/configure-cloudberry.sh
./devops/build/automation/cloudberry/scripts/build-cloudberry.sh

# Copy LICENSE
cp LICENSE "${INSTALL_PREFIX}/"

# Create deb package structure
DEB_BUILD_DIR="${WORKSPACE}/cloudberry-deb"
DEB_PKG_DIR="${DEB_BUILD_DIR}/apache-cloudberry-db_${CLOUDBERRY_VERSION}-${CLOUDBERRY_BUILD}_amd64"
mkdir -p "${DEB_PKG_DIR}/DEBIAN"
mkdir -p "${DEB_PKG_DIR}${INSTALL_PREFIX}"

# Copy installed files
cp -a "${INSTALL_PREFIX}"/* "${DEB_PKG_DIR}${INSTALL_PREFIX}/"

# Runtime dependencies. Ubuntu 24.04+ renamed many libraries in the 64-bit
# time_t transition (libssl3 -> libssl3t64, ...), and 26.04 also moved to
# libxml2-16 and libldap2. entrypoint.sh installs with
# `dpkg -i || apt-get install -f`, which removes the package again if a
# dependency cannot be met, so the names must match the target release.
. /etc/os-release
case "${VERSION_ID}" in
  22.04)
    DEB_DEPENDS="libc6, libssl3, libreadline8, libxml2, libxerces-c3.2, liblz4-1, libzstd1, libapr1, libcurl4, libevent-2.1-7, libkrb5-3, libldap-2.5-0, libpam0g, libuv1, libyaml-0-2"
    ;;
  26.04)
    DEB_DEPENDS="libc6, libssl3t64, libreadline8t64, libxml2-16, libxerces-c3.2t64, liblz4-1, libzstd1, libapr1t64, libcurl4t64, libevent-2.1-7t64, libkrb5-3, libldap2, libpam0g, libuv1t64, libyaml-0-2"
    ;;
  *)
    echo "Unsupported Ubuntu release for the Cloudberry DEB: ${VERSION_ID}" >&2
    exit 1
    ;;
esac

# Create control file
cat > "${DEB_PKG_DIR}/DEBIAN/control" << EOF
Package: apache-cloudberry-db
Version: ${CLOUDBERRY_VERSION}-${CLOUDBERRY_BUILD}
Section: database
Priority: optional
Architecture: amd64
Maintainer: Apache Cloudberry <dev@cloudberry.apache.org>
Description: Apache Cloudberry Database
 Apache Cloudberry is a massively parallel processing (MPP) database
 built on PostgreSQL for analytics and data warehousing.
Depends: ${DEB_DEPENDS}
EOF

# Create postinst script
cat > "${DEB_PKG_DIR}/DEBIAN/postinst" << 'EOF'
#!/bin/bash
set -e
if ! id -u gpadmin >/dev/null 2>&1; then
    useradd -m -s /bin/bash gpadmin
fi
chown -R gpadmin:gpadmin /usr/local/cloudberry-db
echo "Apache Cloudberry Database installed successfully"
EOF

chmod 755 "${DEB_PKG_DIR}/DEBIAN/postinst"

# Build deb package
cd "${DEB_BUILD_DIR}"
dpkg-deb --build "$(basename ${DEB_PKG_DIR})"

DEB_FILE="${DEB_BUILD_DIR}/apache-cloudberry-db_${CLOUDBERRY_VERSION}-${CLOUDBERRY_BUILD}_amd64.deb"
echo "=== DEB Package Created ==="
ls -lh "${DEB_FILE}"
dpkg-deb -I "${DEB_FILE}"
echo "=== Build Complete ==="
