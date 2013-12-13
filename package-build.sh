#!/bin/bash

GIT_BRANCH="$1"
BUILD_NUMBER="$2"
APP='firehose'
ARCH=`dpkg --print-architecture`
DIST_DIR="/mnt/builds/dists"
BINARY_BASE="${APP}/main/binary-${ARCH}"
BINARY_DIR="${DIST_DIR}/${BINARY_BASE}"
PNAME=`/bin/echo $GIT_BRANCH|/bin/sed 's/-/_/g'`
PACKAGE_BASE="pool/${APP}/${PNAME}"
PACKAGE_DIR="${DIST_DIR}/${PACKAGE_BASE}"
INDEX_BASE="${APP}/indexes"
INDEX_DIR="${DIST_DIR}/${INDEX_BASE}"
BUCKET="spaces-releases"
DATE=`date +%Y%m%d%H%M`

if [ ! -d $INDEX_DIR ]; then sudo mkdir -p ${INDEX_DIR}; sudo chown -R deployer:deployer ${INDEX_DIR}; fi
if [ ! -d $PACKAGE_DIR ]; then sudo mkdir -p ${PACKAGE_DIR};sudo chown -R deployer:deployer ${PACKAGE_DIR}; fi
git checkout ${GIT_BRANCH}
git submodule init 
git submodule update
export RAILS_ENV=production

bundle install --deployment

sudo chown -R deployer:deployer .
sudo -udeployer fpm -t deb -s dir -n ${APP} -v ${PNAME} --iteration ${BUILD_NUMBER} -m devops@moxiesoft.com --description "Moxie ${APP} service release - ${GIT_BRANCH} ${BUILD_NUMBER}"  --prefix=/mnt/apps/${APP}/releases/${PNAME} -x "**/config/mongo_norailtie.yml" -x "**/rvm.env" -x "**/.git/**" -x "**/test/**" -p ${PACKAGE_DIR}/${APP}-${PNAME}-${BUILD_NUMBER}.deb .

sudo su - deployer -c "cd ${PACKAGE_DIR};s3cmd sync s3://${BUCKET}/dists/${PACKAGE_BASE}/ ."
sudo su - deployer -c "cd ${DIST_DIR}/${APP};s3cmd sync s3://${BUCKET}/dists/${APP}/ ."

OWD=$PWD
cd /mnt/builds

dpkg-scanpackages -m dists/${PACKAGE_BASE} /dev/null | sudo -udeployer tee ${INDEX_DIR}/${PNAME} > /dev/null

cat ${INDEX_DIR}/*|gzip -c9 |sudo -udeployer tee ${BINARY_DIR}/Packages.gz > /dev/null

sudo su - deployer -c "s3cmd sync ${PACKAGE_DIR}/* s3://${BUCKET}/dists/${PACKAGE_BASE}/ --delete-removed"
sudo su - deployer -c "s3cmd sync ${DIST_DIR}/${APP}/* s3://${BUCKET}/dists/${APP}/"
cd $OWD
