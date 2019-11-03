#!/bin/bash

while getopts f:e:kdr arg
do
    case $arg
    in
        f) ZONEFILE=${OPTARG};;
        e) ENDTIME=$OPTARG;;
        k) GENERATE_KEYS=true;;
        d) REMOVE_OLD_KEYS=true;;
        r) RELOAD=true;;
    esac
done

CWD=$(dirname $ZONEFILE)
cd $CWD

# Default ENDTIME is 90 days from now
if [ -z $ENDTIME ]
then
    ENDTIME="+90d"
fi

# Determine zone from zonefile
ZONE_SOA_REGEX='^\([A-Za-z0-9.]*\)\s*IN\s*SOA\s*.*('
ZONE=`sed -n "s/$ZONE_SOA_REGEX/\1/p" $ZONEFILE`

if [ "$GENERATE_KEYS" = true ]
then
    IFS=$'\n'
    OLD_KEYS=$(grep -oe "K$ZONE.*\+[0-9]\{5\}" $ZONEFILE)
    for KEY in $OLD_KEYS
    do
        echo "Removing key $KEY from $ZONEFILE"
        sed -i".bak" -e "/$KEY/d" $ZONEFILE

        if [ "$REMOVE_OLD_KEYS" = true ]
        then
            echo "Removing keyfiles for key $KEY"
            rm $KEY* 2>/dev/null
        fi
    done
    unset IFS

    KEY="$(dnssec-keygen -a NSEC3RSASHA1 -b 2048 -n ZONE $ZONE)"
    KSK="$(dnssec-keygen -f KSK -a NSEC3RSASHA1 -b 4096 -n ZONE $ZONE)"

    echo "Adding $KEY to $ZONEFILE"
    echo "\$INCLUDE $KEY.key" >> $ZONEFILE
    echo "Adding $KSK to $ZONEFILE"
    echo "\$INCLUDE $KSK.key" >> $ZONEFILE
fi

echo "Signing $ZONE"
SALT=$(head -c 1000 /dev/urandom | sha1sum | cut -b 1-16)  
dnssec-signzone -A -3 $SALT -e $ENDTIME -N INCREMENT -o $ZONE -t $ZONEFILE 

if [ "$RELOAD" = true ]
then
    echo "Reloading $ZONE"
    rndc freeze $ZONE
    rndc reload $ZONE
    rndc thaw $ZONE
fi
