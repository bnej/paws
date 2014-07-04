use File::Find;
use PAWS::Indexer;
use Search::Elasticsearch;

my @paths = @ARGV;

my @index_files = ( );

my $e = Search::Elasticsearch->new( nodes => [ 'localhost:9200' ] );

find( sub {
    my $f = $_;
    if(-d $f) {
    } else {
        if($f =~ m/\.pm$/) {
            push @index_files, $File::Find::name;
        }
    }
}, @paths);

my ($count_in, $count_ix) = ( 0,0 );
local $| = 1;
foreach my $if (@index_files) {
    $count_ix += PAWS::Indexer->index_file($e,$if);
    $count_in ++;
    print("$count_in => $count_ix indexed\r");
}
print("\n");

1;