import time
import urllib2
import re
import sys
from numpy import *

def test_inspire(search):
    pre_url = "http://inspiredev.cern.ch/search?ln=en&p="
    post_url = "&action_search=Search"
    url = pre_url + search + post_url
    start = time.time()
    result = urllib2.urlopen(url).read()
    elapsed = time.time() - start
    if re.search('did not match any record',result):
        return ( 0, elapsed)
    if re.search('returned no hits',result):
        return ( 0, elapsed)
    num = int(re.search('(\d*\,?\d+)</strong> record',result).group(1).replace(',',''))    
    return (num, elapsed)


def test_spires(search):
    pre_url = "http://www.slac.stanford.edu/spires/find/hep/www?"
    post_url = "&server=sunspi5"
    url = pre_url + search + post_url
    start = time.time()
    result = urllib2.urlopen(url).read()
    elapsed = time.time() - start
    if re.search('please try again',result):
        return (0, elapsed)
    num = int(re.search('of <b>(\d+)</b><br>',result).group(1).replace(',',''))    
    return (num, elapsed)

def test(search):
    try:
        ires = test_inspire(search)
    except:
        print "skipping" + search
        ires = [0,0]
    try:    
        sres = test_spires(search)
    except:
        print "skipping" + search
        sres = [0,0]
    sys.stderr.write(search)

    return [ires[0], ires[1],sres[0],sres[1],search]

def test_queries():
    sfile = open('testqueries.txt','r')
    searches= sfile.read().split("\n")
    sfile.close()
    results = [test(lines.rstrip("\n")) for lines in searches]
    errs = filter(lambda r:r[0] < 0 or r[2] < 0, results)
    results = filter(lambda r:r[0] >= 0 and r[2] >= 0, results)
    diffs = filter(lambda r:r[0] <> r[2], results)
    sames = filter(lambda r:r[0] == r[2] > 0, results)
    nulls = filter(lambda r:r[0] == r[2] == 0, results)
    slows = filter(lambda r:r[1] > r[3], results)


    print """
    Searches analyzed   %d
    Equal results         %d
    Different Results     %d
    Null Results          %d

    INSPIRE slow          %d""" % (len(results),len(sames),len(diffs),len(nulls),len(slows))
    
    print "\n\n %d queries with equal results (non-null):\n" % len(sames)
    (ires,itime,sres,stime,search) = transpose(sames)
    spi_av = average(stime.astype(float))
    ins_av = average(itime.astype(float))
    speedup = 100*(spi_av - ins_av )/ spi_av
    print "SPI %.2fs\nINS %.2fs\n          speedup:%d"%(spi_av, ins_av, speedup)


    print """
Queries with different results:
INSPIRE result   SPIRES result    Query
    """
    for s in diffs:
        print "%d  %d  %s" % (s[0],s[2],urllib2.unquote(s[4].replace('+',' ')))

    if len(slows): print """
Queries with slow results:
INSPIRE result,time  SPIRES: result, time   Query
    """
    for s in slows:
        print "%d %.2f     %d %.2f  %s" % (s[0],s[1],s[2],s[3],urllib2.unquote(s[4].replace('+',' '))) 
    
    
if __name__ == "__main__":
    test_queries()

        

