ARG product_version=7.2.1
ARG build_number=34
ARG oo_root='/var/www/onlyoffice/documentserver'

## Setup
FROM onlyoffice/documentserver:${product_version}.${build_number} as setup-stage
ARG product_version
ARG build_number
ARG oo_root

ENV PRODUCT_VERSION=${product_version}
ENV BUILD_NUMBER=${build_number}

ARG build_deps="git make g++ nodejs npm"
RUN apt-get update && apt-get install -y ${build_deps}
RUN npm install -g pkg grunt grunt-cli

WORKDIR /build



## Clone
FROM setup-stage as clone-stage
ARG tag=v${PRODUCT_VERSION}.${BUILD_NUMBER}

RUN git clone --quiet --branch $tag --depth 1 https://github.com/ONLYOFFICE/build_tools.git /build/build_tools
RUN git clone --quiet --branch $tag --depth 1 https://github.com/ONLYOFFICE/server.git      /build/server

# Working mobile editor
RUN git clone --quiet --depth 1 https://github.com/ONLYOFFICE/sdkjs.git       /build/sdkjs
RUN git clone --quiet --depth 1 https://github.com/ONLYOFFICE/web-apps.git    /build/web-apps

## Build
FROM clone-stage as path-stage

# patch
COPY web-apps.patch /build/web-apps.patch
RUN cd /build/web-apps   && git apply /build/web-apps.patch
COPY convertermaster.js /build/server/FileConverter/sources/convertermaster.js
COPY license.js /build/server/Common/sources/license.js
COPY Makefile /build/server/Makefile
COPY server.js /build/server/DocService/sources/server.js
COPY constants.js /build/server/Common/srouces/constants.js
COPY tenantManager.js /build/server/Common/srouces/tenantManager.js

## Build
FROM path-stage as build-stage

# build server with license checks patched
WORKDIR /build/server
RUN make
RUN pkg /build/build_tools/out/linux_/onlyoffice/documentserver/server/FileConverter --targets=node14-linux -o /build/converter
RUN pkg /build/build_tools/out/linux_/onlyoffice/documentserver/server/DocService --targets=node14-linux --options max_old_space_size=4096 -o /build/docservice

# build web-apps with mobile editing
COPY --from=99designs/phantomjs:2.1.1 /usr/local/bin/phantomjs /usr/local/bin/phantomjs
WORKDIR /build/web-apps/build
RUN npm install
RUN grunt --force

## Final image
FROM onlyoffice/documentserver:${product_version}.${build_number}
ARG oo_root

#server
COPY --from=build-stage /build/converter  ${oo_root}/server/FileConverter/converter
COPY --from=build-stage /build/docservice ${oo_root}/server/DocService/docservice

# Restore mobile editing using an old version of mobile editor
COPY --from=build-stage /build/web-apps/deploy/web-apps/apps/documenteditor/mobile     ${oo_root}/web-apps/apps/documenteditor/mobile
COPY --from=build-stage /build/web-apps/deploy/web-apps/apps/presentationeditor/mobile ${oo_root}/web-apps/apps/presentationeditor/mobile
COPY --from=build-stage /build/web-apps/deploy/web-apps/apps/spreadsheeteditor/mobile  ${oo_root}/web-apps/apps/spreadsheeteditor/mobile
