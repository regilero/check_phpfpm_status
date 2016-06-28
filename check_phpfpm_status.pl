#!/usr/bin/perl -w
# check_phpfpm_status.pl
# Version : 0.11
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
# issues & updates: http://github.com/regilero/check_phpfpm_status
use strict;
use Getopt::Long;
use LWP::UserAgent;
use Time::HiRes qw(gettimeofday tv_interval);
use Digest::MD5 qw(md5 md5_hex);

# ensure all outputs are in UTF-8
binmode(STDOUT, ":utf8");

# Nagios specific
# Update Nagios Plugin path according to your platform/installation
use lib "/usr/local/nagios/libexec";
use lib "/usr/local/icinga/libexec";
use lib "/usr/lib/nagios/plugins";
use utils qw($TIMEOUT);

# Globals
my $Version='0.10';
my $Name=$0;

my $o_host =        undef;  # hostname 
my $o_help=         undef;  # want some help ?
my $o_port=         undef;  # port
my $o_url =         undef;  # url to use, if not the default
my $o_user=         undef;  # user for auth
my $o_pass=         '';     # password for auth
my $o_realm=        '';     # password for auth
my $o_version=      undef;  # print version
my $o_warn_p_level= -1;     # Min number of idle workers that will cause a warning
my $o_crit_p_level= -1;     # Min number of idle workersthat will cause an error
my $o_warn_q_level= -1;     # Number of Max Queue Reached that will cause a warning
my $o_crit_q_level= -1;     # Number of Max Queue Reached that will cause an error
my $o_warn_m_level= -1;     # Number of Max Processes Reached that will cause a warning
my $o_crit_m_level= -1;     # Number of Max Processes Reached that will cause an error
my $o_timeout=      15;     # Default 15s Timeout
my $o_warn_thresold=undef;  # warning thresolds entry
my $o_crit_thresold=undef;  # critical thresolds entry
my $o_debug=        undef;  # debug mode
my $o_servername=   undef;  # ServerName (host header in http request)
my $o_https=        undef;  # SSL (HTTPS) mode
my $o_verify_hostname=  0;	# SSL Hostname verification, False by default

my $TempPath = '/tmp/';     # temp path
my $MaxUptimeDif = 60*30;   # Maximum uptime difference (seconds), default 30 minutes

my $phpfpm = 'PHP-FPM'; # Could be used to store version also

# functions
sub show_versioninfo { print "$Name version : $Version\n"; }

sub print_usage {
  print "Usage: $Name -H <host ip> [-p <port>] [-s servername] [-t <timeout>] [-w <WARN_THRESOLD> -c <CRIT_THRESOLD>] [-V] [-d] [-u <url>] [-U user -P pass -r realm]\n";
}
sub nagios_exit {
    my ( $nickname, $status, $message, $perfdata , $silent) = @_;
    my %STATUSCODE = (
      'OK' => 0
      , 'WARNING' => 1
      , 'CRITICAL' => 2
      , 'UNKNOWN' => 3
      , 'PENDING' => 4
    );
    if(!defined($silent)) {
        my $output = undef;
        $output .= sprintf('%1$s %2$s - %3$s', $nickname, $status, $message);
        if ($perfdata) {
            $output .= sprintf('|%1$s', $perfdata);
        }
        $output .= chr(10);
        print $output;
    }
    exit $STATUSCODE{$status};
}

# Get the alarm signal
$SIG{'ALRM'} = sub {
  nagios_exit($phpfpm,"CRITICAL","ERROR: Alarm signal (Nagios timeout)");
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
   Specific URL (only the path part of it in fact) to use, instead of the default "/fpm-status"
-s, --servername=SERVERNAME
   ServerName, (host header of HTTP request) use it if you specified an IP in -H to match the good Virtualhost in your target
-S, --ssl
   Wether we should use HTTPS instead of HTTP
-U, --user=user
   Username for basic auth
-P, --pass=PASS
   Password for basic auth
-r, --realm=REALM
   Realm for basic auth
-d, --debug
   Debug mode (show http request response)
-t, --timeout=INTEGER
   timeout in seconds (Default: $o_timeout)
-w, --warn=MIN_AVAILABLE_PROCESSES,PROC_MAX_REACHED,QUEUE_MAX_REACHED
   number of available workers, or max states reached that will cause a warning
   -1 for no warning
-c, --critical=MIN_AVAILABLE_PROCESSES,PROC_MAX_REACHED,QUEUE_MAX_REACHED
   number of available workers, or max states reached that will cause an error
   -1 for no CRITICAL
-V, --version
   prints version number
-x, --verifyhostname
   verify hostname from ssl cert, set it to 0 to ignore bad hostname from cert

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
  or you have reached the max queue len 5 times. A Warning will be reached for 1 Idle process only.
check_phpfpm_status.pl -H 10.0.0.10 -u /foo/my-fpm-status -s mydomain.example.com -t 8 -w 1,-1,-1 -c 0,2,5

  this will generate WARNING and CRITICAL alerts only on the number of times you have reached the max process
check_phpfpm_status.pl -H 10.0.0.10 -u /foo/my-fpm-status -s mydomain.example.com -t 8 -w -1,10,-1 -c -1,20,-1

  theses two equivalents will not generate any alert (if the php-fpm page is reachable) but could be used for graphics
check_phpfpm_status.pl -H 10.0.0.10 -s mydomain.example.com -w -1,-1,-1 -c -1,-1,-1
check_phpfpm_status.pl -H 10.0.0.10 -s mydomain.example.com
 
  And this one is a basic starting example
check_phpfpm_status.pl -H 127.0.0.1 -s nagios.example.com -w 1,1,1 -c 0,2,2

EOT
}

sub check_options {
    Getopt::Long::Configure ("bundling");
    GetOptions(
      'h'     => \$o_help,         'help'          => \$o_help,
      'd'     => \$o_debug,        'debug'         => \$o_debug,
      'H:s'   => \$o_host,         'hostname:s'    => \$o_host,
      's:s'   => \$o_servername,   'servername:s'  => \$o_servername,
      'S:s'   => \$o_https,        'ssl:s'         => \$o_https,
      'u:s'   => \$o_url,          'url:s'         => \$o_url,
      'U:s'   => \$o_user,         'user:s'        => \$o_user,
      'P:s'   => \$o_pass,         'pass:s'        => \$o_pass,
      'r:s'   => \$o_realm,        'realm:s'       => \$o_realm,
      'p:i'   => \$o_port,         		'port:i'        => \$o_port,
      'V'     => \$o_version,      		'version'       => \$o_version,
      'w=s'   => \$o_warn_thresold,		'warn=s'        => \$o_warn_thresold,
      'c=s'   => \$o_crit_thresold,		'critical=s'    => \$o_crit_thresold,
      't:i'   => \$o_timeout,      		'timeout:i'     		=> \$o_timeout,
      'x:i'   => \$o_verify_hostname,	'verifyhostname:i'		=> \$o_verify_hostname,
    );

    if (defined ($o_help)) { 
        help();
        nagios_exit($phpfpm,"UNKNOWN","leaving","",1);
    }
    if (defined($o_version)) { 
        show_versioninfo();
        nagios_exit($phpfpm,"UNKNOWN","leaving","",1);
    };
    
    if (defined($o_warn_thresold)) {
        ($o_warn_p_level,$o_warn_m_level,$o_warn_q_level) = split(',', $o_warn_thresold);
    }
    if (defined($o_crit_thresold)) {
        ($o_crit_p_level,$o_crit_m_level,$o_crit_q_level) = split(',', $o_crit_thresold);
    }
    if (defined($o_debug)) {
        print("\nDebug thresolds: \nWarning: ($o_warn_thresold) => Min Idle: $o_warn_p_level Max Reached :$o_warn_m_level MaxQueue: $o_warn_q_level");
        print("\nCritical ($o_crit_thresold) => : Min Idle: $o_crit_p_level Max Reached: $o_crit_m_level MaxQueue : $o_crit_q_level\n");
    }
    if ((defined($o_warn_p_level) && defined($o_crit_p_level)) &&
         (($o_warn_p_level != -1) && ($o_crit_p_level != -1) && ($o_warn_p_level <= $o_crit_p_level)) ) { 
        nagios_exit($phpfpm,"UNKNOWN","Check warning and critical values for IdleProcesses (1st part of thresold), warning level must be > crit level!");
    }
    if ((defined($o_warn_m_level) && defined($o_crit_m_level)) &&
         (($o_warn_m_level != -1) && ($o_crit_m_level != -1) && ($o_warn_m_level >= $o_crit_m_level)) ) { 
        nagios_exit($phpfpm,"UNKNOWN","Check warning and critical values for MaxProcesses (2nd part of thresold), warning level must be < crit level!");
    }
    if ((defined($o_warn_q_level) && defined($o_crit_q_level)) &&
         (($o_warn_q_level != -1) && ($o_crit_q_level != -1) && ($o_warn_q_level >= $o_crit_q_level)) ) { 
        nagios_exit($phpfpm,"UNKNOWN","Check warning and critical values for MaxQueue (3rd part of thresold), warning level must be < crit level!");
    }
    # Check compulsory attributes
    if (!defined($o_host)) { 
        print_usage();
        nagios_exit($phpfpm,"UNKNOWN","-H host argument required");
    }
}

########## MAIN ##########

check_options();

my $override_ip = $o_host;
my $ua = LWP::UserAgent->new( 
  protocols_allowed => ['http', 'https'], 
  timeout => $o_timeout,
  ssl_opts => { verify_hostname => $o_verify_hostname }
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
my $proto='http://';
if(defined($o_https)) {
    $proto='https://';
    if (defined($o_port) && $o_port!=443) {
        if (defined ($o_debug)) {
            print "\nDEBUG: Notice: port is defined at $o_port and not 443, check you really want that in SSL mode! \n";
        }
    }
}
if (defined($o_servername)) {
    if (!defined($o_port)) {
        $url = $proto . $o_servername . $o_url;
    } else {
        $url = $proto . $o_servername . ':' . $o_port . $o_url;
    }
} else {
    if (!defined($o_port)) {
        $url = $proto . $o_host . $o_url;
    } else {
        $url = $proto . $o_host . ':' . $o_port . $o_url;
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
    $webcontent=$response->decoded_content( charset_strict=>1, raise_error => 1, alt_charset => 'none' );
    if (defined ($o_debug)) {
        print "\nDEBUG: HTTP response:";
        print $response->status_line;
        print "\n".$response->header('Content-Type');
        print "\n";
        print $webcontent;
    }
    if ($response->header('Content-Type') =~ m/text\/html/) {
        nagios_exit($phpfpm,"CRITICAL", "We have a response page for our request, but it's an HTML page, quite certainly not the status report of php-fpm");
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
        #$phpfpm .= "-".$Pool;
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
    my $LastMaxListenQueue = 0;
    if ((-e $TempFile) && (-r $TempFile) && (-w $TempFile))
    {
        open ($FH, '<',$TempFile) or nagios_exit($phpfpm,"UNKNOWN","unable to read temporary data from :".$TempFile);
        $LastUptime = <$FH>;
        $LastAcceptedConn = <$FH>;
        $LastMaxChildrenReached = <$FH>;
        $LastMaxListenQueue = <$FH>;
        close ($FH);
        if (defined ($o_debug)) {
            print ("\nDebug: data from temporary file:\n");
            print ("LastUptime: $LastUptime LastAcceptedConn: $LastAcceptedConn LastMaxChildrenReached: $LastMaxChildrenReached LastMaxListenQueue: $LastMaxListenQueue \n");
        }
    }
    
    open ($FH, '>'.$TempFile) or nagios_exit($phpfpm,"UNKNOWN","unable to write temporary data in :".$TempFile);
    print $FH "$Uptime\n"; 
    print $FH "$AcceptedConn\n";
    print $FH "$MaxChildrenReached\n";
    print $FH "$MaxListenQueue\n";
    close ($FH);
  
    my $ReqPerSec = 0;
    my $Accesses = 0;
    my $MaxChildrenReachedNew = 0;
    my $MaxListenQueueNew = 0;
    # check only if this counter may have been incremented
    # but not if it may have been too much incremented
    # and something should have happened in the server
    if ( ($Uptime>$LastUptime) 
      && ($Uptime-$LastUptime<$MaxUptimeDif)
      && ($AcceptedConn>=$LastAcceptedConn)
      && ($MaxListenQueue>=$LastMaxListenQueue)
      && ($MaxChildrenReached>=$LastMaxChildrenReached)) {
        $ReqPerSec = ($AcceptedConn-$LastAcceptedConn)/($Uptime-$LastUptime);
        $Accesses = ($AcceptedConn-$LastAcceptedConn);
        $MaxChildrenReachedNew = ($MaxChildrenReached-$LastMaxChildrenReached);
        $MaxListenQueueNew = ($MaxListenQueue-$LastMaxListenQueue);
    }

    $InfoData = sprintf ("%s, %.3f sec. response time, Busy/Idle %d/%d,"
                 ." (max: %d, reached: %d), ReqPerSec %.1f, "
                 ."Queue %d (len: %d, reached: %d)"
                 ,$Pool,$timeelapsed, $ActiveProcesses, $IdleProcesses
                 ,$MaxActiveProcesses,$MaxChildrenReachedNew
                 ,$ReqPerSec,$ListenQueue,$ListenQueueLen,$MaxListenQueueNew);

    $PerfData = sprintf ("Idle=%d Busy=%d MaxProcesses=%d MaxProcessesReach=%d "
                 ."Queue=%d MaxQueueReach=%d QueueLen=%d ReqPerSec=%f"
                 ,($IdleProcesses),($ActiveProcesses),($MaxActiveProcesses)
                 ,($MaxChildrenReachedNew),($ListenQueue),($MaxListenQueueNew)
                 ,($ListenQueueLen),$ReqPerSec);
    # first all critical exists by priority
    if (defined($o_crit_q_level) && (-1!=$o_crit_q_level) && ($MaxListenQueueNew >= $o_crit_q_level)) {
        nagios_exit($phpfpm,"CRITICAL", "Max queue reached is critically high " . $InfoData,$PerfData);
    }
    if (defined($o_crit_m_level) && (-1!=$o_crit_m_level) && ($MaxChildrenReachedNew >= $o_crit_m_level)) {
        nagios_exit($phpfpm,"CRITICAL", "Max processes reached is critically high " . $InfoData,$PerfData);
    }
    if (defined($o_crit_p_level) && (-1!=$o_crit_p_level) && ($IdleProcesses <= $o_crit_p_level)) {
        nagios_exit($phpfpm,"CRITICAL", "Idle workers are critically low " . $InfoData,$PerfData);
    }
    # Then WARNING exits by priority
    if (defined($o_warn_q_level) && (-1!=$o_warn_q_level) && ($MaxListenQueueNew >= $o_warn_q_level)) {
        nagios_exit($phpfpm,"WARNING", "Max queue reached is high " . $InfoData,$PerfData);
    }
    if (defined($o_warn_m_level) && (-1!=$o_warn_m_level) && ($MaxChildrenReachedNew >= $o_warn_m_level)) {
        nagios_exit($phpfpm,"WARNING", "Max processes reached is high " . $InfoData,$PerfData);
    }
    if (defined($o_warn_p_level) && (-1!=$o_warn_p_level) && ($IdleProcesses <= $o_warn_p_level)) {
        nagios_exit($phpfpm,"WARNING", "Idle workers are low " . $InfoData,$PerfData);
    }
    
    nagios_exit($phpfpm,"OK",$InfoData,$PerfData);
    
} else {
    nagios_exit($phpfpm,"CRITICAL", $response->status_line);
}
