#!/bin/bash
ok=0;
nok=0;

function test_last_check() {
    res=$1
    expected=$2
    if [ "$?" -ne 0 ]; then
        echo " ^^^^" 2>&1
        echo " \=> FAILED TEST : last Check result [${$res}] is not the expected one [${expected}]" 2>&1
        echo ""
        let nok+=1
    else
        echo " \=> TEST is OK"
        echo ""
        let ok+=1
    fi
}

echo " * Checking phpfpm is fastcgi mode --------------------------------------"
./check_phpfpm_status.pl -H 127.0.0.1 -p 9001 -u /check-status --fastcgi
test_last_check ${?} 0


echo " * Request the phpinfo page, -will fail the check -----------------------"
./check_phpfpm_status.pl -H 127.0.0.1 -p 9001 -u /usr/src/app/index.php --fastcgi
test_last_check ${?} 1

echo " * Checking phpfpm is fastcgi mode --------------------------------------"
./check_phpfpm_status.pl -H 127.0.0.1 -p 9001 -u /check-status --fastcgi
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