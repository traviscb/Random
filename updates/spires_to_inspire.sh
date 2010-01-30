#! /bin/sh


#

SPIRES_DIR="/afs/slac.stanford.edu/g/library/inspire/data"
UPDATES="/u2/spires/slaclib/inspire/"
cd $SPIRES_DIR

umask 002
#
# get updates from sunspi4
# doesn't work as cron
#scp sunspi4:${UPDATES}*.compilation .
#scp sunspi4:${UPDATES}*.today .


# new files to hold the updates 
KEYS="updates."`date +%Y%m%d%H%M%S`
BACKUP="fullupdate."${KEYS}

rm updates*

#mv result.compilation ${BACKUP}
mv result.today ${BACKUP}

#touch result.compilation
split -l20000 ${BACKUP} ${KEYS} 


# new files to hold the removes 
REMS="remove."`date +%Y%m%d`
REMOVE_BU="fullremove."${KEYS}

rm remove.*

#mv removes.compilation ${REMOVE_BU}
mv removes.today ${REMOVE_BU}
#touch removes.compilation
split -l20000 ${REMOVE_BU} ${REMS} 


#put back the empty compilation files
#scp *.compilation sunspi4:${UPDATES} 

#
#

for file in ${KEYS}?? ; do
    /afs/slac/g/library/bin/spiresdump.pl -tinspire_update -s ${file};
    rm ${file};
done


for file in ${REMS}??; do
    /afs/slac/g/library/bin/spiresdump.pl -r -tinspire_update -s ${file};
    rm ${file};
done





#
# remove all empty files
find public/ -size -24c -follow -exec rm {} \;
