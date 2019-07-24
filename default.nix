with import <nixpkgs> {
  overlays = [
    (import (builtins.fetchGit { url = "git@gitlab.intr:_ci/nixpkgs.git"; ref = "master"; }))
  ];
};

let

inherit (builtins) concatMap getEnv toJSON;
inherit (dockerTools) buildLayeredImage;
inherit (lib) concatMapStringsSep firstNChars flattenSet dockerRunCmd buildPhpPackage mkRootfs;
inherit (lib.attrsets) collect isDerivation;
inherit (stdenv) mkDerivation;

locale = glibcLocales.override {
  allLocales = false;
  locales = [ "en_US.UTF-8/UTF-8" ];
};

sh = dash.overrideAttrs (_: rec {
  postInstall = ''
    ln -s dash "$out/bin/sh"
  '';
});

php71 = mkDerivation rec {
  name = "php-7.1.30";
  src = fetchurl {
    url = "https://www.php.net/distributions/php-7.1.30.tar.bz2";
    sha256 = "664850774fca19d2710b9aa35e9ae91214babbde9cd8d27fd3479cc97171ecb3";
  };
  patches = [ ./patch/php7/fix-paths-php7.patch ];
  stripDebugList = "bin sbin lib modules";
  outputs = [ "out" "dev" ];
  enableParallelBuilding = true;
  buildInputs = [
    autoconf
    automake
    pkgconfig
    curl
    apacheHttpd
    bison
    bzip2
    flex
    freetype
    gettext
    gmp
    icu
    icu.dev
    libzip
    libjpeg
    libmcrypt
    libmhash
    libpng
    libxml2
    xorg.libXpm.dev
    libxslt
    mariadb
    pam
    pcre
    postgresql
    readline
    sqlite
    uwimap
    zlib
    libiconv
    t1lib
    libtidy
    kerberos
    openssl.dev
    glibcLocales
  ];
  CXXFLAGS = "-std=c++11";
  configureFlags = [
    "--disable-cgi"
    "--disable-phpdbg"
    "--disable-maintainer-zts"
    "--disable-debug"
    "--disable-fpm"
    "--disable-ipv6"
    "--enable-pdo"
    "--enable-dom"
    "--enable-libxml"
    "--enable-inline-optimization"
    "--enable-dba"
    "--enable-bcmath"
    "--enable-soap"
    "--enable-sockets"
    "--enable-zip"
    "--enable-intl"
    "--enable-exif"
    "--enable-ftp"
    "--enable-mbstring"
    "--enable-calendar"
    "--enable-gd-native-ttf"
    "--enable-sysvsem"
    "--enable-sysvshm"
    "--enable-opcache"
    "--with-config-file-scan-dir=/etc/php.d"
    "--with-pcre-regex=${pcre.dev} PCRE_LIBDIR=${pcre}"
    "--with-imap=${uwimap}"
    "--with-imap-ssl"
    "--with-mhash"
    "--with-libzip"
    "--with-curl=${curl.dev}"
    "--with-zlib=${zlib.dev}"
    "--with-libxml-dir=${libxml2.dev}"
    "--with-xmlrpc"
    "--with-readline=${readline.dev}"
    "--with-pdo-sqlite=${sqlite.dev}"
    "--with-pgsql=${postgresql}"
    "--with-pdo-pgsql=${postgresql}"
    "--with-pdo-mysql=mysqlnd"
    "--with-mysqli=mysqlnd"
    "--with-gd"
    "--with-freetype-dir=${freetype.dev}"
    "--with-png-dir=${libpng.dev}"
    "--with-jpeg-dir=${libjpeg.dev}"
    "--with-gmp=${gmp.dev}"
    "--with-openssl"
    "--with-gettext=${gettext}"
    "--with-xsl=${libxslt.dev}"
    "--with-mcrypt=${libmcrypt}"
    "--with-bz2=${bzip2.dev}"
    "--with-tidy=${html-tidy}"
    "--with-apxs2=${apacheHttpd.dev}/bin/apxs"
  ];
  hardeningDisable = [ "bindnow" ];
  preConfigure = ''
    # Don't record the configure flags since this causes unnecessary
    # runtime dependencies
    for i in main/build-defs.h.in scripts/php-config.in; do
      substituteInPlace $i \
        --replace '@CONFIGURE_COMMAND@' '(omitted)' \
        --replace '@CONFIGURE_OPTIONS@' "" \
        --replace '@PHP_LDFLAGS@' ""
    done
    [[ -z "$libxml2" ]] || addToSearchPath PATH $libxml2/bin
    export EXTENSION_DIR=$out/lib/php/extensions
    configureFlags+=(--with-config-file-path=$out/etc \
      --includedir=$dev/include)
     ./buildconf --force
  '';
  postFixup = ''
    mkdir -p $dev/bin $dev/share/man/man1
    mv $out/bin/phpize $out/bin/php-config $dev/bin/
    mv $out/share/man/man1/phpize.1.gz \
      $out/share/man/man1/php-config.1.gz \
      $dev/share/man/man1/
  '';
};

buildPhp71Package = args: buildPhpPackage ({ php = php71; } // args);

php71Packages = {
  redis = buildPhp71Package {
    name = "redis";
    version = "4.2.0";
    sha256 = "7655d88addda89814ad2131e093662e1d88a8c010a34d83ece5b9ff45d16b380";
  };

  timezonedb = buildPhp71Package {
    name = "timezonedb";
    version ="2019.1";
    sha256 = "0rrxfs5izdmimww1w9khzs9vcmgi1l90wni9ypqdyk773cxsn725";
  };

  rrd = buildPhp71Package {
    name = "rrd";
    version = "2.0.1";
    sha256 = "39f5ae515de003d8dad6bfd77db60f5bd5b4a9f6caa41479b1b24b0d6592715d";
    inputs = [ pkgconfig rrdtool ];
  };

  memcached = buildPhp71Package {
    name = "memcached";
    version = "3.1.3";
    sha256 = "20786213ff92cd7ebdb0d0ac10dde1e9580a2f84296618b666654fd76ea307d4";
    inputs = [ pkgconfig zlib.dev libmemcached ];
    configureFlags = [
      "--with-zlib-dir=${zlib.dev}"
      "--with-libmemcached-dir=${libmemcached}"
    ];
  };

  imagick = buildPhp71Package {
    name = "imagick";
    version = "3.4.3";
    sha256 = "1f3c5b5eeaa02800ad22f506cd100e8889a66b2ec937e192eaaa30d74562567c";
    inputs = [ pkgconfig imagemagick.dev pcre ];
    configureFlags = [ "--with-imagick=${imagemagick.dev}" ];
  };

  libsodiumPhp = buildPhp71Package {
    name = "libsodium";
    version = "2.0.21";
    sha256 = "1sqz5987mg02hd90v695606qj5klpcrvzwfbj0yvg60vakbk3sz4";
    inputs = [ libsodium.dev ];
    configureFlags = [ "--with-sodium=${libsodium.dev}" ];
  };
};

rootfs = mkRootfs {
  name = "apache2-php71-rootfs";
  src = ./rootfs;
  inherit curl coreutils findutils apacheHttpdmpmITK apacheHttpd mjHttpErrorPages php71 postfix s6 execline;
  ioncube = ioncube.v71;
  s6PortableUtils = s6-portable-utils;
  s6LinuxUtils = s6-linux-utils;
  mimeTypes = mime-types;
  libstdcxx = gcc-unwrapped.lib;
};

dockerArgHints = {
    init = false;
    read_only = true;
    network = "host";
    environment = { HTTPD_PORT = "$SOCKET_HTTP_PORT"; PHP_INI_SCAN_DIR = ":${rootfs}/etc/phpsec/$SECURITY_LEVEL"; };
    tmpfs = [
      "/tmp:mode=1777"
      "/run/bin:exec,suid"
    ];
    ulimits = [
      { name = "stack"; hard = -1; soft = -1; }
    ];
    security_opt = [ "apparmor:unconfined" ];
    cap_add = [ "SYS_ADMIN" ];
    volumes = [
      ({ type = "bind"; source =  "$SITES_CONF_PATH" ; target = "/read/sites-enabled"; read_only = true; })
      ({ type = "bind"; source =  "/etc/passwd" ; target = "/etc/passwd"; read_only = true; })
      ({ type = "bind"; source =  "/etc/group" ; target = "/etc/group"; read_only = true; })
      ({ type = "bind"; source = "/opcache"; target = "/opcache"; })
      ({ type = "bind"; source = "/home"; target = "/home"; })
      ({ type = "bind"; source = "/opt/postfix/spool/maildrop"; target = "/var/spool/postfix/maildrop"; })
      ({ type = "bind"; source = "/opt/postfix/spool/public"; target = "/var/spool/postfix/public"; })
      ({ type = "bind"; source = "/opt/postfix/lib"; target = "/var/lib/postfix"; })
      ({ type = "tmpfs"; target = "/run"; })
    ];
  };

gitAbbrev = firstNChars 8 (getEnv "GIT_COMMIT");

in 

pkgs.dockerTools.buildLayeredImage rec {
  maxLayers = 124;
  name = "docker-registry.intr/webservices/apache2-php71";
  tag = if gitAbbrev != "" then gitAbbrev else "latest";
  contents = [
    rootfs
    tzdata
    locale
    postfix
    sh
    coreutils
    perl
    perl528Packages.Mojolicious
    perl528Packages.base
    perl528Packages.libxml_perl
    perl528Packages.libnet
    perl528Packages.libintl_perl
    perl528Packages.LWP 
    perl528Packages.ListMoreUtilsXS
    perl528Packages.LWPProtocolHttps
  ] ++ collect isDerivation php71Packages;
  config = {
    Entrypoint = [ "${rootfs}/init" ];
    Env = [
      "TZ=Europe/Moscow"
      "TZDIR=${tzdata}/share/zoneinfo"
      "LOCALE_ARCHIVE_2_27=${locale}/lib/locale/locale-archive"
      "LC_ALL=en_US.UTF-8"
    ];
    Labels = flattenSet rec {
      ru.majordomo.docker.arg-hints-json = builtins.toJSON dockerArgHints;
      ru.majordomo.docker.cmd = dockerRunCmd dockerArgHints "${name}:${tag}";
      ru.majordomo.docker.exec.reload-cmd = "${apacheHttpd}/bin/httpd -d ${rootfs}/etc/httpd -k graceful";
    };
  };
}
