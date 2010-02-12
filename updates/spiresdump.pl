#! /usr/local/bin/perl

=pod

=head1 SYNOPSIS

spiresdump.pl -t<destination> -y<firstyear> -l<lastyear> -f<format>
    -s<search> -c<also_criteria>  -m -r

dumps spires recrds from first year to last year in a given format  depending on destination.

Tries to take care of many character encoding issues.

-m moves things to a final location

-r interprests the key file given in -s (for inspire_update) as keys to remove

=cut

use Expect::Spires;
use Date::Calc qw(This_Year Today_and_Now);
use Getopt::Std;
use Pod::Usage;
use File::Temp (tempfile);

my $hep = Expect::Spires->new(database => "hep", timeout => "36000");

my ($tmpfh, $tmpfile) = tempfile(DIR => '/tmp/');

%args=();
getopts('mrht:y:l:s:f:c:',\%args);

die( pod2usage(-verbose=>2)) if $args{h};

$TEST=$INSPIRE=$AUTHORCLAIM = 0;

if ($args{t} =~ /test/i){
    $TEST = 1;
}
elsif ($args{t} =~ /authorclaim/i ){
    $AUTHORCLAIM = 1;
}
elsif ($args{t} =~ /inspire_update/i){
    $INSPIRE_UPDATE = 1;
}
elsif ($args{t} =~ /inspire/i){
    $INSPIRE = 1;
}



$begin = "<results>";
$end = "</results>";
$START_WITH_ALL_OLD = 1;
$stamp = '';

if ($TEST){
    $DIR = 'test/';
    $FIRST_YEAR = 1995;
    $criteria = "cnum occ > 0";
    $init_search = "find author brooks";
    $LAST_YEAR = 2009;
    $FORMAT = "xmlinspire";
    $start = "<records>";
    $end = "</records>";
    $begin = '';    
}
elsif ($AUTHORCLAIM){
    $DIR = 'authorclaim/';
    $FIRST_YEAR = 1964;
    $LAST_YEAR = This_Year;
    $FORMAT = "xmlpublic";
    $criteria = "bull occ = 0";
    $rsync_dest = "mamf@mamf.openlib.org:opt/spires";
}
elsif ($INSPIRE){
    $DIR = 'inspire/';
    $FIRST_YEAR = 1964;
    $LAST_YEAR = This_Year;
    $FORMAT = "xmlinspire";
    $start = "<records>";
    $end = "</records>";
    $begin = '';
}
elsif ($INSPIRE_UPDATE){
    $DIR = '/afs/slac/g/library/inspire/data/public/';
    $FIRST_YEAR = 1964;
    $LAST_YEAR = This_Year;
    $FORMAT = "xmlinspire";
    $start = "<records>";
    $end = "</records>";
    $begin = '';
    $irnlist = `pwd`;
    chomp($irnlist);
    $irnlist .= '/'.$args{s};
    $string = $args{s};
    $string =~ s/^.*\.(\d+)$/$1/;

    $stack = "STACK.".$string;
    $stamp = $string;
    $active = '/tmp/'.$args{s};
    if ( $args{r}) {
	$stamp =~ s/_update_/remove_/;
    }
    else{
	system('perl -i -pe \'s/^\s*(\d+)/sta $1/\' '.$irnlist);
	system("cp $irnlist $active");
	print $hep->ask("use $active","clr stack", "xeq", "store $stack repl");
	print "stack stored as: $stack\n";
    }


}

else{
    $DIR = 'searchdumps/';
    $FIRST_YEAR = 1964 ;
    $LAST_YEAR = This_Year;
    $FORMAT = $args{f};
    $init_search = $args{s};
    $criteria = $args{c};
    $start = "<records>";
    $end = "</records>";
    $begin = '';
}

    
my $outdir = $DIR =~ m{^/} ? $DIR : "/fulltext/scratch/dumps/".$DIR;     

if ($args{r}){
    $outfile = $outdir.$date.$stamp.".xml";
    open(OUT, ">${outfile}.marcxml" ) || die "error opening $outfile: $!";
    open(REMOVES, "<$irnlist") || die  "error opening $removes: $!";
    print OUT '<?xml version="1.0" encoding="UTF-8"?>
<collection xmlns="http://www.loc.gov/MARC21/slim">
';
    for $line (<REMOVES>){
	chomp;
	$line =~ s/\s+//g;
	print OUT '<record>
<datafield tag="970" ind1=" " ind2=" "><subfield code="a">SPIRES-'.$line.'</subfield></datafield>
<datafield tag="980" ind1=" " ind2=" "><subfield code="a">Deleted</subfield></datafield>
</record>';
    }
    print OUT '</collection>';
    close(OUT);
    close(REMOVES);
}
else {

    if ($args{y}) { 
	$FIRST_YEAR = $args{y};
	$START_WITH_ALL_OLD = 0;
    }
    if ($args{l}) { $LAST_YEAR = $args{l};}
    $hep->ask("set format $FORMAT","set length 255");
    
    for $date ( $FIRST_YEAR .. $LAST_YEAR){
	printset($date, $criteria);
    }
}


if ($args{m} && $rsync_dest){
    system("rsync -avz --delete $outdir/*.xml $rsync_dest");
}


sub printset{
    $date = shift;
    $criteria = shift;
    if ($date == $FIRST_YEAR && $START_WITH_ALL_OLD ){
	$search = "date <= $date or date occ = 0";
    }
    else{
	$search = "date = $date";
    }
    if ($criteria) {
	$search = "$search and $criteria";
    }
    $outfile = $outdir.$date.$stamp.".xml";
    print $hep->ask("use $outfile","clr act", "wdse $begin");
    if ($init_search){
	print ($hep->ask($init_search, "for res where $search"));
	print "$init_search\nfor res where $search\n";
    }
    elsif ($stack){
	print ($hep->ask("for stack where $search"));
	print "restore @".$stack."\nfor stack where $search\n";
    }
    else{
	print {$hep->ask("for subf where $search")}[0]; 
	print "for subf where $search\n";
    }

    print $hep->ask("in act cln con dis all, end=' wdse $start'","wdse $end", "use tcb");
    
    print "Created $outfile\n";
    system("iconv  -fISO-8859-1 -tUTF-8 $outfile > $tmpfile");
    system(' perl -0777 -pe \'s{\n}{ }g;s{\p{IsCntrl}}{ }g\' '.$tmpfile.' | perl -pe \'s{(\</\w+\>)}{$1\n}g\' | perl -pe \'s/[^[:ascii:]]//g;\' > '.$outfile);


}



=item destination 

<destination> can be one of several shortcuts that override the explicit
    format/search/criteria choices.:

=over

inspire 
authorclaim 
test

=back

=item dates

dates default to pre1965 to current year

=item -m

executed a move after generating the files to put them in a final location
depending on destination (krichels server for author claim, inspire bets etc)


=cut
