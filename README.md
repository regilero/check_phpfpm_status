# CHECK_PHPFPM_STATUS

Nagios check checking the fpm-status page report from php-fpm. Tracking Idle processes, max processes reached and process queue.

Support of http, https and fastgi direct mode.

You can use this script to draw some graphics (perfparse).

PHP-FPM Monitor for Nagios version 1.2

GPL licence, (c)2012 Leroy Regis

[![Build Status](https://api.travis-ci.org/regilero/check_phpfpm_status.svg?branch=master)](https://api.travis-ci.org/regilero/check_phpfpm_status.svg?branch=master)

# Installation

## Dependencies

You need **perl**.

If you use the script to request the php status page from a web service (usual
case) you'll need the perl library, LWP::UserAgent (`apt-get install liblwp-protocol-https-perl` on Debian)

If you request the php status page without http support, directly in fastcgi, (that's not the usual case) you
will need the FCGI::Client CPAN library. On debian:

    sudo perl -MCPAN -e shell
    install Bundle::CPAN
    reload cpan
    install FCGI::Client

If you have **cpanm** installed, and only if you experience problems, you can
install all potential dependencies by running (maybe with sudo for global install) :

    cpanm -n --skip-satisfied --installdeps .

This command uses the cpanfile provided with this script to list dependencies.
You may not have this file, as the check_phpfpm_status.pl script is quite standalone,
but you can find this file, and the tests files on the github page of the project.
https://github.com/regilero/check_phpfpm_status

## Install of this script

1.  Copy check_phpfpm_status.pl to the server's nagios plugins directory.
2.  Ensure the script has execution rights

## Icinga2 configuration

Copy `check_phpfpm_status.icinga2.conf` to the icinga2 zone.

Define a new service for all Linux hosts with `vars.phpfpm`, for example:

```
apply Service "PHP-fpm process" {
  import "generic-service"
  check_command = "phpfpm"
  vars.phpfpm_user = "user"
  vars.phpfpm_pass = "pass"
  vars.phpfpm_url = "/status"
  vars.phpfpm_critical = "0,2,5"
  command_endpoint = host.vars.client_endpoint
  assign where host.vars.client_endpoint && host.vars.os == "Linux" && host.vars.phpfpm
}
```

# Script Documentation

```
Usage: ./check_phpfpm_status.pl -H <host ip> [-p <port>] [-s servername] [-t <timeout>] [-w <WARN_THRESOLD> -c <CRIT_THRESOLD>] [-V] [-d] [-f] [-u <url>] [-U user -P pass -r realm]
-h, --help
   print this help message
-H, --hostname=HOST
   name or IP address of host to check
-p, --port=PORT
   Http port, or Fastcgi port when using --fastcgi
-u, --url=URL
   Specific URL (only the path part of it in fact) to use, instead of the default "/fpm-status"
-s, --servername=SERVERNAME
   ServerName, (host header of HTTP request) use it if you specified an IP in -H to match the good Virtualhost in your target
-f, --fastcgi
   Connect directly to php-fpm via network or local socket, using fastcgi protocol instead of HTTP.
-U, --user=user
   Username for basic auth
-P, --pass=PASS
   Password for basic auth
-r, --realm=REALM
   Realm for basic auth
-d, --debug
   Debug mode (show http request response)
-t, --timeout=INTEGER
   timeout in seconds (Default: 15)
-S, --ssl
   Wether we should use HTTPS instead of HTTP. Note that you can give some extra parameters to this settings. Default value is 'TLSv1'
   but you could use things like 'TLSv1_1' or 'TLSV1_2' (or even 'SSLv23:!SSLv2:!SSLv3' for old stuff).
-x, --verifyssl, --verifyhostname
   verify certificate and hostname from ssl cert, default is 0 (no security), set it to 1 to really make SSL peer name and certificater checks.
   'verifyhostname' is the old deprecated name of this option.
-X, --cacert
   Full path to the cacert.pem certificate authority used to verify ssl certificates (use with --verifyssl).
   if not given the cacert from Mozilla::CA cpan plugin will be used.
-w, --warn=MIN_AVAILABLE_PROCESSES,PROC_MAX_REACHED,QUEUE_MAX_REACHED
   number of available workers, or max states reached that will cause a warning
   -1 for no warning
-c, --critical=MIN_AVAILABLE_PROCESSES,PROC_MAX_REACHED,QUEUE_MAX_REACHED
   number of available workers, or max states reached that will cause an error
   -1 for no CRITICAL
-V, --version
   prints version number

Note :
  3 items can be managed on this check, this is why -w and -c parameters are using 3 values thresolds
  - MIN_AVAILABLE_PROCESSES: Working with the number of available (Idle) and working process (Busy).
    Generating WARNING and CRITICAL if you do not have enough Idle processes.
  - PROC_MAX_REACHED: the fpm-status report will show us how many times the max processes were reached sinc start,
    this script will record how many time this happended since last check, letting you fix thresolds for alerts
  - QUEUE_MAX_REACHED: the php-fpm report will show us how many times the max queue was reached since start,
    this script will record how many time this happended since last check, letting you fix thresolds for alerts

Examples:

  This will lead to CRITICAL if you have 0 Idle process, or you have reached the max processes 2 times between last check,
  or you have reached the max queue len 5 times. A Warning will be reached for 1 Idle process only:

check_phpfpm_status.pl -H 10.0.0.10 -u /foo/my-fpm-status -s mydomain.example.com -t 8 -w 1,-1,-1 -c 0,2,5

  this will generate WARNING and CRITICAL alerts only on the number of times you have reached the max process:

check_phpfpm_status.pl -H 10.0.0.10 -u /foo/my-fpm-status -s mydomain.example.com -t 8 -w -1,10,-1 -c -1,20,-1

  theses two equivalents will not generate any alert (if the php-fpm page is reachable) but could be used for graphics:

check_phpfpm_status.pl -H 10.0.0.10 -s mydomain.example.com -w -1,-1,-1 -c -1,-1,-1
check_phpfpm_status.pl -H 10.0.0.10 -s mydomain.example.com

  And this one is a basic starting example :

check_phpfpm_status.pl -H 127.0.0.1 -s nagios.example.com -w 1,1,1 -c 0,2,2

  All these examples used an HTTP proxy (like Nginx or Apache) in front of php-fpm. If php-fpm is listening on a tcp/ip socket
  you can also make a direct request on this port (9000 by default) using the fastcgi protocol. You'll need the FastCGI client
  tools enabled in Perl (check the README) and the command would use the -f or --fastcgi option (note that SSL or servername
  options are useless in this mode).
  This can be especially usefull if you use php-fpm in an isolated env, without the HTTP proxy support (like in a docker container):

check_phpfpm_status.pl -H 127.0.0.1 --fastcgi -p 9002 -w 1,1,1 -c 0,2,2

HTTPS/SSL:

  Adding --ssl you can reach an https host:

check_phpfpm_status.pl -H 10.0.0.10 -s mydomain.example.com --ssl

  Check --verify-ssl (false by defaut) --cacert and --sl for more options, like below
  (note that certificate checks never wortked on my side, add -d for full debug and
  tell me if it worked for you, you may need up to date CPAN adn openSSL libs)

check_phpfpm_status.pl -H 10.0.0.10 -s mydomain.example.com --ssl TLSv1_2 --verify-ssl 1 --cacert /etc/ssl/cacert.pem
```

# LICENSE

GNU GPL v3
