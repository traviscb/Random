import invenio.bibauthorid_webinterface as bwi
import invenio.bibauthorid_personid_tables_utils as bai
from invenio.search_engine import get_record, perform_request_search
from invenio.dbquery import run_sql
import sys.argv

def find_pids_for_insp_ids(insp_ids):
    ''' Take a list of INSPIRE Ids ( INSPIRE-XXX) (IID) and generate a
    list of IID -> PID (Person IDs from aidPERSON) mappings.  Uses several
    BibAuthorID functions and guesses the best match based on overlap
    between cluster and the list of papers with the IID.

    @param insp_ids: list of INSPIRE Ids (stripped of "INSPIRE-")
    @return mapping of IID -> dictionary (pid -> PID, author_cluster -> # recs i the aid cluster, inspire_search -> # recs having the IID, matches -> # recs in both sets)

    '''

    mapping = {}
    verbose = 0
    for iid in insp_ids:
        poss_recs = perform_request_search(p="100__i:INSPIRE-"+iid +" | 700__i:INSPIRE-" + iid)
        mapping[iid] = {'pid':0,'matches':0,'author_cluster':0,'inspire_search':len(poss_recs)}
        if len(poss_recs)==0:
            continue
        for author in get_authors(get_record(poss_recs[0])):
            ad = dict(author[0])
            if ad.has_key('i'):
                name = ad['a']
                insp_id = ad['i']
                insp_id = insp_id.split('-')[1]
                if insp_id == iid:
                    high_match = 0
                    res = bwi.webapi.search_person_ids_by_name(name)
                    if len(res) > 0:
                        for possible_id in res:
                            pid = possible_id[0]
                            if verbose > 0:
                                print "found pid "+ str(pid) + " for " + name
                            recs = bwi.webapi.get_papers_by_person_id(pid)
                            recs = [int(row[0]) for row in recs]
                            num = len(recs)
                            match = len(set(recs).intersection(set(poss_recs)))
                            if match > high_match:
                                print str(pid) + " matches INSP " + str(iid)  +" with " + str(match) + " of " + str(num) + " and " + str(len(poss_recs))
                                mapping[iid] = {'pid':pid,'matches':match,'author_cluster':num,'inspire_search':len(poss_recs)}
                                high_match = match
    return(mapping)


def get_authors(record):
    '''return the author fields 100/700s in one list from a record

    @param record: a record object from get_record
    @return a list of author objects like record[100][0]
    '''
    authors = []
    if record.has_key('100'):
        authors.append(record['100'][0])
    if record.has_key('700'):
        authors.extend(record['700'])
    return(authors)

def find_insp_ids():
    '''Collect inspire ids from the DB

    @return list of recids with inspire ids in the record
    '''


    ids = run_sql("select value from bib10x where value like 'INSPIRE%'")
    ids2 = run_sql("select value from bib70x where value like 'INSPIRE%'")
    ids = set(ids).union(set(ids2))
    return([a[0].split('-')[1] for a in ids])


def check_cluster(insp_id, pid = None, name = None):
    '''PRints useful diagnostic information about a cluster.  Likely to be
    called like:

      [check_cluster(x[0], x[1]['pid']) for x in mapping if x[1]['pid'] >0]

    @param insp_id: The inspire ID of the cluster (leave off "INSPIRE-")
    @param pid: Default=None   The PID of the aid cluster to compare to,
    may be set to the corresponding one from the mapping, or not
    @param name: Default=None  The name to lookup in aidPERSON (Not useful
    at the moment'''

    poss_recs = perform_request_search(p="100__i:INSPIRE-"+insp_id +" | 700__i:INSPIRE-"+insp_id)
    if len(poss_recs)>0:
         for auth in get_authors(get_record(poss_recs[0])):
             ad = dict(auth[0])
             if ad.has_key('i') and  ad['i']=='INSPIRE-' + insp_id:
                 print "INSPIRE ids on %d papers, such as:" % (len(poss_recs),)
                 print "     %d: %s" % (poss_recs[0],str(ad),)
                 name = ad['a']
    if pid:
         names = [x[1] for x in bai.get_person_data(pid) if  x[0]=='gathered_name']
         print "\nCluster contains %d names: %s" % (len(names), str(names))
         recs = bwi.webapi.get_papers_by_person_id(pid)
         recs = [int(row[0]) for row in recs]
         num = len(recs)
         print "Cluster contains %d papers" % (num,)
         match = len(set(recs).intersection(set(poss_recs)))
         print "   of which %d match " % (match,)
    if name:
         print "\nBAI found %d possible persons" % (len(bai.find_personIDs_by_name_string(name)),)


    print "------------"


def get_statistics(mapping):
    '''gets statistics on the "goodness" of a mapping between pids and
    IIDs.   Parameters on the FRACTION and DIFFERENCE between the inspire
    id searches and the document count in the matched clusters determine
    that a given correspondence is either GOOD, BAD, or CLOSE, or FAIL.

    @param mapping: dictionary of iid -> data from find_pids_for_insp_ids
    @return tuple of dictionaries, iid:containing dicts of good, bad, fail and
    close iids  stats:containing statistics about the good, bad and close
    assignments
    @rtype tuple
    '''
    FRACTION_CUTOFF = 0.9
    DIFF_CUTOFF = 3
    stats = {}
    iids = {}
    for typ in ['good','bad','close','fail']:
        stats[typ]=[]
        iids[typ]=[]

    def add_to_typ(iids,stats,typ,iid,match):
            iids[typ].append(iid)
            stats[typ].append((match['matches'],match['inspire_search'],match['author_cluster']))
            return(iids,stats)

    for (iid, match) in mapping.iteritems():
        if match['matches']==0:
            (iids,stats) = add_to_typ(iids,stats,'fail',iid, match)
            continue
        if match['inspire_search'] == match['matches'] or match['author_cluster'] == match['matches']:
            (iids, stats) = add_to_typ(iids,stats,'good',iid, match)
            continue
        min_match = min(match['author_cluster'],match['inspire_search'])
        fraction = float(match['matches'])/min_match
        if min_match - match['matches'] < DIFF_CUTOFF:
            (iids, stats) = add_to_typ(iids,stats,'close',iid, match)
            continue
        if fraction > FRACTION_CUTOFF:
            (iids, stats) = add_to_typ(iids,stats,'close',iid, match)
        else:
            (iids, stats) = add_to_typ(iids,stats,'bad',iid, match)
    alg_succ = 0
    alg_total = 0
    for typ in ['good','bad','close', 'fail']:
        sum_match = 0
        sum_iid = 0
        sum_clus = 0
        for row in stats[typ]:
            sum_match += row[0]
            sum_iid += row[1]
            sum_clus += row[2]
        print "%d of type %s\n  matches:%d IIDs:%d  Clustered:%d" % (len(stats[typ]),typ,sum_match,sum_iid,sum_clus)
        if typ in ['good','close','bad']:
            alg_succ += sum_match
            alg_total += sum_iid

    print "--------\nAlgorithm Success: %f  (good, close and bad matches/total possible iid recs)"% (alg_succ/float(alg_total))

    print "--------\nProfile Success: %f  %d profiles accepted  [ignoring %s fails]" % ((len(stats['good'])+len(stats['close']))/float(len(mapping)-len(stats['fail'])),len(mapping)-len(stats['fail']),len(stats['fail']))
    return(iids, stats)


def set_insp_ids(mapping):
    ''' uses a mapping of inspi ids to PIDs to set info in aidPERSON
    tables.   Should be used when mapping is finalized

    @param mapping: dictionary of iid -> data from find_pids_for_insp_ids
    '''
    for (iid,data) in mapping.iteritems():
         bai.set_person_data(data['pid'],'inspire_id',iid)


def print_insp_ids(mapping):
    ''' uses a mapping of inspi ids to PIDs to set info in aidPERSON
    tables.   Should be used when mapping is finalized

    @param mapping: dictionary of iid -> data from find_pids_for_insp_ids
    '''
    for (iid,data) in mapping.iteritems():
         print "INSPIRE id %d  ->  %d" % iid, data['pid']


def main():
    sys.argv = argv[1]
    cutoff = 20
    #    get_statistics(find_pids_for_insp_ids(find_insp_ids()[0:cutoff]))
    mapping = find_pids_for_insp_ids(iids[0:cutoff])
    print_insp_ids(mapping)
