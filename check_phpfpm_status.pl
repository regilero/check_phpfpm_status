#!/usr/bin/perl -w
# check_phpfpm_status.pl
# Version : 0.2
# Author  : regis.leroy at makina-corpus.com
#           based on previous apache status work by Dennis D. Spreen (dennis at spreendigital.de)
#						Based on check_apachestatus.pl v1.4 by 
#						    De Bodt Lieven (Lieven.DeBodt at gmail.com)
#						    Karsten Behrens (karsten at behrens dot in)
#		    				Geoff McQueen (geoff.mcqueen at hiivesystems dot com )
#				    		Dave Steinberg (dave at redterror dot net)
# Licence : GPL - http://www.fsf.org/licenses/gpl.txt
#
# help : ./check_phpfpm_status.pl -h
#
use strict;
use Getopt::Long;
use LWP::UserAgent;
use Time::HiRes qw(gettimeofday tv_interval);
use Digest::MD5 qw(md5 md5_hex);


# Nagios specific
use lib "/usr/local/nagios/libexec";
use utils qw($TIMEOUT);


# Globals
my $Version='0.2';
my $Name=$0;

my $o_host =        undef;  # hostname 
my $o_help=         undef;  # want some help ?
my $o_port=         undef;  # port
my $o_url =         undef;  # url to use, if not the default
my $o_user=         undef;  # user for auth
my $o_pass=         '';     # password for auth
my $o_realm=        '';     # password for auth
my $o_version=      undef;  # print version
my $o_warn_level=   undef;  # Number of available slots that will cause a warning
my $o_crit_level=   undef;  # Number of available slots that will cause an error
my $o_timeout=      15;     # Default 15s Timeout
my $o_maxreach=     undef;  # number of max processes reach since last check
my $o_debug=        undef;  # debug mode
my $o_servername=   undef;  # ServerName (host heaéder in http request)

my $TempPath = '/tmp/';     # temp path
my $MaxUptimeDif = 60*30;   # Maximum uptime difference (seconds), default 30 minutes

my $phpfpm = 'PHP-FPM'; # Could be used to store version also

# functions
sub show_versioninfo { print "$Name version : $Version\n"; }

sub print_usage {
  print "Usage: $Name -H <host ip> [-p <port>] [-s servername] [-t <timeout>] [-m maxProc] [-w <warn_level> -c <crit_level>] [-V] [-d] [-u <url>] [-U user -P pass -r realm]\n";
}
sub nagios_exit {
    my ( $nickname, $status, $message, $perfdata ) = @_;
    my %STATUSCODE = (
      'OK' => 0
      , 'WARNING' => 1
      , 'CRITICAL' => 2
      , 'UNKNOWN' => 3
      , 'PENDING' => 4
    );
    my $output = undef;
    $output .= sprintf('%1$s %2$s - %3$s', $nickname, $status, $message);
    if ($perfdata) {
        $output .= sprintf('|%1$s', $perfdata);
    }
    $output .= chr(10);
    print $output;
    exit $STATUSCODE{$status};
}

# Get the alarm signal
$SIG{'ALRM'} = sub {
  nagios_exit("PHP-FPM","CRITICAL","ERROR: Alarm signal (Nagios timeout)");
};

sub help {
  print "PHP-FPM Monitor for Nagios version ",$Version,"\n";
  print "GPL licence, (c)2012 Leroy Regis\n\n";
  print_usage();
  print <<EOT;
-h, --help
   print this help message
-H, --hostname=HOST
   name or IP address of host to check
-p, --port=PORT
   Http port
-u, --url=URL
   Specific URL to use, instead of the default "http://<hostname or IP>/fpm-status"
-s, --servername=SERVERNAME
   ServerName, (host header of HTTP request) use it if you specified an IP in -H to match the good Virtulahost in your target
-U, --user=user
   Username for basic auth
-P, --pass=PASS
   Password for basic auth
-r, --realm=REALM
   Realm for basic auth
-d, --debug
   Debug mode (show http request response)
-m, --maxreach=MAX
   Number of max processes reached (since last check) that should trigger an alert
-t, --timeout=INTEGER
   timeout in seconds (Default: $o_timeout)
-w, --warn=MIN
   number of available workers that will cause a warning
   -1 for no warning
-c, --critical=MIN
   number of available workers that will cause an error
   -1 for no CRITICAL
-V, --version
   prints version number

Example: 

  check_phpfpm_status.pl -H 10.0.0.10 -u /foo/my-fpm-status -s mydomain.example.com -m 5 -w 1 -c 0 -t 8

Note :
  The script will return
    * Without warn and critical options:
        OK       if we are able to connect to the php-fpm server's status page,
        CRITICAL if we aren't able to connect to the php-fpm server's status page,,
    * With warn and critical options:
        OK       if we are able to connect to the php-fpm server's status page and #available workers > <warn_level>,
        WARNING  if we are able to connect to the php-fpm server's status page and #available workers <= <warn_level>,
        CRITICAL if we are able to connect to the php-fpm server's status page and #available workers <= <crit_level>,
        CRITICAL if we aren't able to connect to the php-fpm server's status page

EOT
}

sub check_options {
    Getopt::Long::Configure ("bundling");
    GetOptions(
      'h'     => \$o_help,        'help'          => \$o_help,
      'd'     => \$o_debug,       'debug'         => \$o_debug,
      'H:s'   => \$o_host,        'hostname:s'    => \$o_host,
      's:s'   => \$o_servername,  'servername:s'  => \$o_servername,
      'u:s'   => \$o_url,         'url:s'         => \$o_url,
      'U:s'   => \$o_user,        'user:s'        => \$o_user,
      'P:s'   => \$o_pass,        'pass:s'        => \$o_pass,
      'r:s'   => \$o_realm,       'realm:s'       => \$o_realm,
      'p:i'   => \$o_port,        'port:i'        => \$o_port,
      'V'     => \$o_version,     'version'       => \$o_version,
      'w:i'   => \$o_warn_level,  'warn:i'        => \$o_warn_level,
      'c:i'   => \$o_crit_level,  'critical:i'    => \$o_crit_level,
      't:i'   => \$o_timeout,     'timeout:i'     => \$o_timeout,
      'm:i'   => \$o_maxreach,    'maxreach:i'    => \$o_maxreach,
    );

    if (defined ($o_help)) { 
        help();
        nagios_exit("PHP-FPM","UNKNOWN","leaving");
    }
    if (defined($o_version)) { 
        show_versioninfo();
        nagios_exit("PHP-FPM","UNKNOWN","leaving");
    };
    if (((defined($o_warn_level) && !defined($o_crit_level)) || 
        (!defined($o_warn_level) && defined($o_crit_level))) || 
        ((defined($o_warn_level) && defined($o_crit_level)) && 
         (($o_warn_level != -1) &&  ($o_warn_level <= $o_crit_level))
        )
       ) { 
        nagios_exit("PHP-FPM","UNKNOWN","Check warn and crit!");
    }
    # Check compulsory attributes
    if (!defined($o_host)) { 
        print_usage();
        nagios_exit("PHP-FPM","UNKNOWN","-H host argument required");
    }
}

########## MAIN ##########

check_options();

my $override_ip = $o_host;
my $ua = LWP::UserAgent->new( 
  protocols_allowed => ['http', 'https'], 
  timeout => $o_timeout
);
# we need to enforce the HTTP request is made on the Nagios Host IP and
# not on the DNS related IP for that domain
@LWP::Protocol::http::EXTRA_SOCK_OPTS = ( PeerAddr => $override_ip );
# this prevent used only once warning in -w mode
my $ua_settings = @LWP::Protocol::http::EXTRA_SOCK_OPTS;

my $timing0 = [gettimeofday];
my $response = undef;
my $url = undef;

if (!defined($o_url)) {
    $o_url='/fpm-status';
} else {
    # ensure we have a '/' as first char
    $o_url = '/'.$o_url unless $o_url =~ m(^/)
}

if (defined($o_servername)) {
    if (!defined($o_port)) {
        $url = 'http://' . $o_servername . $o_url;
    } else {
        $url = 'http://' . $o_servername . ':' . $o_url;
    }
} else {
    if (!defined($o_port)) {
        $url = 'http://' . $o_host . $o_url;
    } else {
        $url = 'http://' . $o_host . ':' . $o_port . $o_url;
    }
}
if (defined ($o_debug)) {
    print "\nDEBUG: HTTP url: \n";
    print $url;
}

my $req = HTTP::Request->new( GET => $url );

if (defined($o_servername)) {
    $req->header('Host' => $o_servername);
}
if (defined($o_user)) {
    $req->authorization_basic($o_user, $o_pass);
}

if (defined ($o_debug)) {
    print "\nDEBUG: HTTP request: \n";
    print "IP used (better if it's an IP):" . $override_ip . "\n";
    print $req->as_string;
}
$response = $ua->request($req);
my $timeelapsed = tv_interval ($timing0, [gettimeofday]);

my $InfoData = '';
my $PerfData = '';

my $webcontent = undef;
if ($response->is_success) {
    $webcontent=$response->decoded_content;
    if (defined ($o_debug)) {
        print "\nDEBUG: HTTP response:";
        print $response->status_line;
        print "\n";
        print $webcontent;
    }
    # example of response content expected:
    #pool:                 foobar
    #process manager:      dynamic
    #start time:           31/Jan/2012:08:18:45 +0000
    #start since:          845
    #accepted conn:        7
    #listen queue:         0
    #max listen queue:     0
    #listen queue len:     0
    #idle processes:       2
    #active processes:     2
    #total processes:      4
    #max active processes: 2
    #max children reached: 0

    my $Pool = '';
    if($webcontent =~ m/pool: (.*?)\n/) {
        $Pool = $1;
        $Pool =~ s/^\s+|\s+$//g;
        $phpfpm .= "-".$Pool;
    }
    
    my $Uptime = 0;
    if($webcontent =~ m/start since: (.*?)\n/) {
        $Uptime = $1;
        $Uptime =~ s/^\s+|\s+$//g;
    }
    
    my $AcceptedConn = 0;
    if($webcontent =~ m/accepted conn: (.*?)\n/) {
        $AcceptedConn = $1;
        $AcceptedConn =~ s/^\s+|\s+$//g;
    }
    
    my $ActiveProcesses= 0;
    if($webcontent =~ m/(.*)?\nactive processes: (.*?)\n/) {
        $ActiveProcesses = $2;
        $ActiveProcesses =~ s/^\s+|\s+$//g;
    }
    
    my $TotalProcesses= 0;
    if($webcontent =~ m/total processes: (.*?)\n/) {
        $TotalProcesses = $1;
        $TotalProcesses =~ s/^\s+|\s+$//g;
    }
    
    my $IdleProcesses= 0;
    if($webcontent =~ m/idle processes: (.*?)\n/) {
        $IdleProcesses = $1;
        $IdleProcesses =~ s/^\s+|\s+$//g;
    }
    
    my $MaxActiveProcesses= 0;
    if($webcontent =~ m/max active processes: (.*?)\n/) {
        $MaxActiveProcesses = $1;
        $MaxActiveProcesses =~ s/^\s+|\s+$//g;
    }
    
    my $MaxChildrenReached= 0;
    if($webcontent =~ m/max children reached: (.*?)\n/) {
        $MaxChildrenReached = $1;
        $MaxChildrenReached =~ s/^\s+|\s+$//g;
    }
    
    my $ListenQueue= 0;
    if($webcontent =~ m/\nlisten queue: (.*?)\n/) {
        $ListenQueue = $1;
        $ListenQueue =~ s/^\s+|\s+$//g;
    }
    
    my $ListenQueueLen= 0;
    if($webcontent =~ m/listen queue len: (.*?)\n/) {
        $ListenQueueLen = $1;
        $ListenQueueLen =~ s/^\s+|\s+$//g;
    }
    
    my $MaxListenQueue= 0;
    if($webcontent =~ m/max listen queue: (.*?)\n/) {
        $MaxListenQueue = $1;
        $MaxListenQueue =~ s/^\s+|\s+$//g;
    }
    # Debug
    if (defined ($o_debug)) {
        print ("\nDEBUG Parse results => Pool:" . $Pool . "\nAcceptedConn:" . $AcceptedConn . "\nActiveProcesses:" . $ActiveProcesses . " TotalProcesses :".$TotalProcesses . " IdleProcesses :" .$IdleProcesses . "\nMaxActiveProcesses :" . $MaxActiveProcesses . " MaxChildrenReached :" . $MaxChildrenReached . "\nListenQueue :" . $ListenQueue . " ListenQueueLen : " .$ListenQueueLen . " MaxListenQueue: " . $MaxListenQueue ."\n");
    }

    my $TempFile = $TempPath.$o_host.'_check_phpfpm_status'.md5_hex($url);
    my $FH;
    
    my $LastUptime = 0;
    my $LastAcceptedConn = 0;
    my $LastMaxChildrenReached = 0;
    if ((-e $TempFile) && (-r $TempFile) && (-w $TempFile))
    {
        open ($FH, '<',$TempFile) or nagios_exit($phpfpm,"UNKNOWN","unable to read temporary data from :".$TempFile);
        $LastUptime = <$FH>;
        $LastAcceptedConn = <$FH>;
        $LastMaxChildrenReached = <$FH>;
        close ($FH);
    }
    
    open ($FH, '>'.$TempFile) or nagios_exit($phpfpm,"UNKNOWN","unable to write temporary data in :".$TempFile);
    print $FH "$Uptime\n"; 
    print $FH "$AcceptedConn\n";
    print $FH "$MaxChildrenReached\n";
    close ($FH);
  
    my $ReqPerSec = 0;
    my $Accesses = 0;
    my $MaxChildrenReachedNew = 0;
    # check only if this counter may have been incremented
    # but not if it may have been too much incremented
    # and something should have happened in the server
    if ( ($Uptime>$LastUptime) 
      && ($Uptime-$LastUptime<$MaxUptimeDif)
      && ($AcceptedConn>=$LastAcceptedConn)
      && ($MaxChildrenReached>=$LastMaxChildrenReached)) {
        $ReqPerSec = ($AcceptedConn-$LastAcceptedConn)/($Uptime-$LastUptime);
        $Accesses = ($AcceptedConn-$LastAcceptedConn);
        $MaxChildrenReachedNew = ($MaxChildrenReached-$LastMaxChildrenReached);
    }

    $InfoData = sprintf ("%.3f sec. response time, Busy/Idle %d/%d,"
                 ." total %d/%d (max reach: %d), ReqPerSec %.1f, "
                 ."Queue %d/%d (len : %d)"
                 ,$timeelapsed, $ActiveProcesses, $IdleProcesses
                 ,$TotalProcesses, $MaxActiveProcesses,$MaxChildrenReachedNew
                 ,$ReqPerSec,$ListenQueue,$MaxListenQueue,$ListenQueueLen);

    $PerfData = sprintf ("Idle=%d;Busy=%d;MaxProcesses=%d;MaxProcessesReach=%d;"
                 ."Queue=%d;MaxQueue=%d;QueueLen=%d;ReqPerSec=%f"
                 ,($IdleProcesses),($ActiveProcesses),($MaxActiveProcesses)
                 ,($MaxChildrenReachedNew),($ListenQueue),($MaxListenQueue)
                 ,($ListenQueueLen),$ReqPerSec);

    if (defined($o_maxreach) && ($MaxChildrenReachedNew >= $o_maxreach)) {
        nagios_exit($phpfpm,"CRITICAL", "Max processes reached too much " . $InfoData,$PerfData);
    }
    if (defined($o_crit_level) && ($o_crit_level != -1)) {
        if ( ($MaxActiveProcesses-$ActiveProcesses) <= $o_crit_level) {
            nagios_exit($phpfpm,"CRITICAL", "Idle workers critically low " . $InfoData,$PerfData);
        }
    } 
    if (defined($o_warn_level) && ($o_warn_level != -1)) {
        if ( ($MaxActiveProcesses-$ActiveProcesses) <= $o_warn_level) {
            nagios_exit($phpfpm,"WARNING", "Idle workers low " . $InfoData,$PerfData);
        }
    }
    
    nagios_exit($phpfpm,"OK",$InfoData,$PerfData);
    
} else {
    nagios_exit($phpfpm,"CRITICAL", $response->status_line);
}
