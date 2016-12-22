#!/bin/bash
ok=0;
nok=0;

function test_last_check() {
    res=$1
    expected=$2
    if [ "x${res}" == "x${expected}" ]; then
        echo " \=> TEST is OK ("${res}" == "${expected}")"
        echo ""
        let ok+=1
    else
        echo " ^^^^" 2>&1
        echo " \=> FAILED TEST : last Check result ("${res}") is not the expected one ("${expected}")" 2>&1
        echo ""
        let nok+=1
    fi
}

echo " ------------------------------------------------------------------------"
echo "                FASTCGI MODE"
echo " ------------------------------------------------------------------------"
echo
echo " * Checking phpfpm in fastcgi mode --------------------------------------"
./check_phpfpm_status.pl -H 127.0.0.1 -p 9001 -u /check-status --fastcgi
test_last_check ${?} 0

echo " * Request the phpinfo page, -will fail the check -----------------------"
./check_phpfpm_status.pl -H 127.0.0.1 -p 9001 -u /usr/src/app/index.php --fastcgi
test_last_check ${?} 2

echo " * Checking phpfpm in fastcgi mode --------------------------------------"
./check_phpfpm_status.pl -H 127.0.0.1 -p 9001 -u /check-status --fastcgi
test_last_check ${?} 0


echo " ------------------------------------------------------------------------"
echo "                HTTP MODE"
echo " ------------------------------------------------------------------------"
echo
echo " * Checking phpfpm in http mode : no server name, should fail ----------"
./check_phpfpm_status.pl -t 15 -H 127.0.0.1 -p 8801 -s -u /check-status
test_last_check ${?} 2

echo " * Checking phpfpm in http mode : bad server name, should fail ----------"
./check_phpfpm_status.pl -t 15 -H 127.0.0.1 -p 8801 -s doesnotexists.example.com -u /check-status
test_last_check ${?} 2

echo " * Checking phpfpm in http mode : right server name ---------------------"
./check_phpfpm_status.pl -t 15 -H 127.0.0.1 -p 8801 -s phpfpm.example.com -u /check-status
test_last_check ${?} 0

echo " * Checking phpfpm in http mode : right server name, bad url-------------"
./check_phpfpm_status.pl -t 15 -H 127.0.0.1 -p 8801 -s phpfpm.example.com -u /checkstatus
test_last_check ${?} 2

echo " ------------------------------------------------------------------------"
echo "                HTTPS MODE"
echo " ------------------------------------------------------------------------"
echo

echo " * Checking phpfpm in https mode, https on http port failre--------------"
./check_phpfpm_status.pl -t 15 -H 127.0.0.1 -p 8801 -s phpfpm.example.com -u /check-status --ssl
test_last_check ${?} 2

echo " * Checking phpfpm in https mode, https on http port failre--------------"
./check_phpfpm_status.pl -t 15 -H 127.0.0.1 -p 8443 -s phpfpm.example.com -u /check-status --ssl
test_last_check ${?} 0

echo
echo "**** FINAL TESTS STATUS ****"
echo " TESTS OK: ${ok}"
echo " FAILED TESTS: ${nok}"
if [ "x${nok}" == "x0" ]; then
    echo "++++ SUCCESS ++++" 2>&1
    exit 0
else
    echo "---- FAILURE ---- (${nok} fail(s))" 2>&1
    exit 1
fi