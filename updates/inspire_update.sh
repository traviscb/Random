#! /bin/sh

# should be run as apache...
#

SPIRES_DIR="/afs/slac.stanford.edu/public/groups/library/spires/inspire/updates"
INSPIRE_DIR="/afs/cern.ch/project/inspire/updates/"

cd $INSPIRE_DIR

MINS=`echo "scale= 0;(((\`date +%s\` - \`date +%s -r lastupdate\` )/60))"|bc -l`


echo "looking for updates produced in the last ${MINS} minutes" 
touch lastupdate
find $SPIRES_DIR -type f -mmin -$MINS -exec cp '{}' . \; 

#remove empty files
grep -l "<records> </records>" *.xml |xargs rm 



for file in *.xml; do 
    /usr/bin/xsltproc SPIRES2MARC.xsl ${file}>| done/${file}.marcxml ;
    rm ${file} ;
    /opt/cds-invenio/bin/bibupload -ir done/${file}.marcxml ;
done 

for file in *.marcxml; do
    mv ${file}  done/${file} ;
    /opt/cds-invenio/bin/bibupload -ir done/${file} ;
done